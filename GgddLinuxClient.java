import javax.swing.*;
import java.awt.*;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.io.File;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.nio.file.attribute.FileAttribute;
import java.nio.file.attribute.PosixFilePermissions;
import java.util.*;

/** Small native Linux front end for the GGDD desktop Mihomo controller. */
public final class GgddLinuxClient {
    private static final String API = System.getenv().getOrDefault(
        "GGDD_CONTROLLER", "http://127.0.0.1:19091");
    private static final Path PROFILE = Path.of(System.getenv().getOrDefault(
        "GGDD_PROFILE", "runtime/profile.yaml"));
    private final HttpClient http = HttpClient.newHttpClient();
    private JFrame frame;
    private final JComboBox<String> groups = new JComboBox<>();
    private final DefaultListModel<String> nodes = new DefaultListModel<>();
    private final JList<String> nodeList = new JList<>(nodes);
    private final JLabel state = new JLabel("Connecting to GGDD...");
    private Map<String, Object> proxies = Map.of();

    public static void main(String[] args) throws Exception {
        if (args.length == 2 && args[0].equals("--export")) {
            Path out = exportProfile(Path.of(args[1]));
            System.out.println("Exported Clash YAML to " + out + " (mode 600, contains proxy credentials)");
            return;
        }
        if ((args.length == 1 && args[0].equals("--list")) ||
            (args.length == 0 && GraphicsEnvironment.isHeadless())) {
            if (GraphicsEnvironment.isHeadless())
                System.out.println("No graphical display detected; listing GGDD groups instead.");
            Map<String, Object> root = asMap(new Json(fetch("/proxies").body()).parse());
            for (Map.Entry<String, Object> e : asMap(root.get("proxies")).entrySet()) {
                Map<String, Object> p = asMap(e.getValue());
                if ("Selector".equals(string(p.get("type"))))
                    System.out.printf("%s\t%s\t%d nodes%n", e.getKey(), string(p.get("now")), asList(p.get("all")).size());
            }
            return;
        }
        SwingUtilities.invokeLater(() -> new GgddLinuxClient().show());
    }

    private static HttpResponse<String> fetch(String path) throws Exception {
        return HttpClient.newHttpClient().send(HttpRequest.newBuilder(URI.create(API + path)).GET().build(), HttpResponse.BodyHandlers.ofString());
    }

    private void show() {
        frame = new JFrame("GGDD Linux Client");
        frame.setDefaultCloseOperation(WindowConstants.EXIT_ON_CLOSE);
        frame.setSize(720, 480);
        frame.setLocationByPlatform(true);
        JButton refresh = new JButton("Refresh");
        JButton use = new JButton("Use selected node");
        JButton export = new JButton("Export Clash YAML");
        groups.addActionListener(e -> populateNodes());
        refresh.addActionListener(e -> load());
        use.addActionListener(e -> selectNode());
        export.addActionListener(e -> exportYaml());
        JPanel top = new JPanel(new BorderLayout(8, 8));
        top.add(new JLabel("Proxy group:"), BorderLayout.WEST);
        top.add(groups, BorderLayout.CENTER);
        top.add(refresh, BorderLayout.EAST);
        JPanel bottom = new JPanel(new BorderLayout(8, 8));
        bottom.add(use, BorderLayout.WEST);
        bottom.add(state, BorderLayout.CENTER);
        bottom.add(export, BorderLayout.EAST);
        frame.add(top, BorderLayout.NORTH);
        frame.add(new JScrollPane(nodeList), BorderLayout.CENTER);
        frame.add(bottom, BorderLayout.SOUTH);
        frame.setVisible(true);
        load();
    }

    private void load() {
        state.setText("Loading...");
        new SwingWorker<Map<String, Object>, Void>() {
            protected Map<String, Object> doInBackground() throws Exception {
                return asMap(new Json(fetch("/proxies").body()).parse());
            }
            protected void done() {
                try {
                    proxies = asMap(get().get("proxies"));
                    groups.removeAllItems();
                    for (Map.Entry<String, Object> e : proxies.entrySet()) {
                        if ("Selector".equals(string(asMap(e.getValue()).get("type")))) groups.addItem(e.getKey());
                    }
                    if (groups.getItemCount() > 0) groups.setSelectedIndex(0);
                    state.setText("Connected to " + API);
                } catch (Exception e) { state.setText("GGDD unavailable: " + e.getMessage()); }
            }
        }.execute();
    }

    private void populateNodes() {
        nodes.clear();
        Map<String, Object> p = asMap(proxies.get(String.valueOf(groups.getSelectedItem())));
        for (Object n : asList(p.get("all"))) nodes.addElement(string(n));
        String now = string(p.get("now"));
        if (!now.isBlank()) nodeList.setSelectedValue(now, true);
    }

    private void selectNode() {
        String group = String.valueOf(groups.getSelectedItem());
        String node = nodeList.getSelectedValue();
        if (node == null || group.equals("null")) return;
        state.setText("Switching to " + node + "...");
        new SwingWorker<Void, Void>() {
            protected Void doInBackground() throws Exception {
                HttpRequest req = HttpRequest.newBuilder(URI.create(API + "/proxies/" + enc(group)))
                    .header("Content-Type", "application/json")
                    .PUT(HttpRequest.BodyPublishers.ofString("{\"name\":\"" + json(node) + "\"}"))
                    .build();
                HttpResponse<String> r = http.send(req, HttpResponse.BodyHandlers.ofString());
                if (r.statusCode() / 100 != 2) throw new IllegalStateException("HTTP " + r.statusCode());
                return null;
            }
            protected void done() { try { get(); state.setText("Selected " + node); load(); } catch (Exception e) { state.setText("Switch failed: " + e.getMessage()); } }
        }.execute();
    }

    private void exportYaml() {
        if (!Files.isReadable(PROFILE)) {
            state.setText("No profile to export at " + PROFILE.toAbsolutePath());
            return;
        }
        JFileChooser chooser = new JFileChooser(new File(System.getProperty("user.home"), "Desktop"));
        chooser.setDialogTitle("Export Clash YAML (contains your proxy credentials)");
        chooser.setSelectedFile(new File(chooser.getCurrentDirectory(), "ggdd-clash.yaml"));
        if (chooser.showSaveDialog(frame) != JFileChooser.APPROVE_OPTION) return;
        File target = chooser.getSelectedFile();
        if (target.exists() && JOptionPane.showConfirmDialog(frame, target.getName() + " exists. Overwrite?",
            "Export Clash YAML", JOptionPane.YES_NO_OPTION) != JOptionPane.YES_OPTION) return;
        try {
            Path out = exportProfile(target.toPath());
            state.setText("Exported to " + out + " (mode 600, keep it private)");
        } catch (Exception e) { state.setText("Export failed: " + e.getMessage()); }
    }

    /** Writes the cached subscription profile as a portable Clash/Mihomo YAML with owner-only permissions. */
    private static Path exportProfile(Path target) throws java.io.IOException {
        String yaml = Files.readString(PROFILE, StandardCharsets.UTF_8)
            .replaceAll("(?m)^interface-name:.*\\R", "")
            .replaceAll("(?m)^allow-lan:.*$", "allow-lan: false")
            .replaceAll("(?m)^bind-address:.*$", "bind-address: '127.0.0.1'");
        FileAttribute<?> ownerOnly = PosixFilePermissions.asFileAttribute(PosixFilePermissions.fromString("rw-------"));
        Path dir = target.toAbsolutePath().getParent();
        Path tmp = Files.createTempFile(dir, ".ggdd-export", ".tmp", ownerOnly);
        try {
            Files.writeString(tmp, yaml, StandardCharsets.UTF_8);
            Files.move(tmp, target.toAbsolutePath(), StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE);
        } finally { Files.deleteIfExists(tmp); }
        return target.toAbsolutePath();
    }

    private static String enc(String s) { return s.replace("%", "%25").replace("/", "%2F").replace(" ", "%20"); }
    private static String json(String s) { return s.replace("\\", "\\\\").replace("\"", "\\\""); }
    private static String string(Object o) { return o == null ? "" : String.valueOf(o); }
    @SuppressWarnings("unchecked") private static Map<String, Object> asMap(Object o) { return o instanceof Map ? (Map<String, Object>) o : Map.of(); }
    @SuppressWarnings("unchecked") private static java.util.List<Object> asList(Object o) { return o instanceof java.util.List ? (java.util.List<Object>) o : java.util.List.of(); }

    private static final class Json {
        private final String s; private int i;
        Json(String s) { this.s = s; }
        Object parse() { skip(); return value(); }
        private Object value() { skip(); char c=s.charAt(i); if(c=='{')return object(); if(c=='[')return array(); if(c=='\"')return str(); if(s.startsWith("true",i)){i+=4;return true;} if(s.startsWith("false",i)){i+=5;return false;} if(s.startsWith("null",i)){i+=4;return null;} int b=i; while(i<s.length() && ",]} \n\r\t".indexOf(s.charAt(i))<0)i++; return s.substring(b,i); }
        private Map<String,Object> object(){ Map<String,Object> m=new LinkedHashMap<>(); i++; skip(); while(s.charAt(i)!='}'){String k=str();skip();i++;m.put(k,value());skip();if(s.charAt(i)==','){i++;skip();}}i++;return m; }
        private java.util.List<Object> array(){java.util.List<Object> a=new ArrayList<>();i++;skip();while(s.charAt(i)!=']'){a.add(value());skip();if(s.charAt(i)==','){i++;skip();}}i++;return a;}
        private String str(){StringBuilder b=new StringBuilder();i++;while(s.charAt(i)!='\"'){char c=s.charAt(i++);if(c=='\\'&&i<s.length()){char e=s.charAt(i++);b.append(e=='n'?'\n':e=='r'?'\r':e=='t'?'\t':e);}else b.append(c);}i++;return b.toString();}
        private void skip(){while(i<s.length()&&Character.isWhitespace(s.charAt(i)))i++;}
    }
}
