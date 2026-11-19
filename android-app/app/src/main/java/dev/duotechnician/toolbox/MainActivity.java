package dev.duotechnician.toolbox;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.ActivityNotFoundException;
import android.content.Intent;
import android.content.res.ColorStateList;
import android.graphics.Typeface;
import android.os.Build;
import android.os.Bundle;
import android.os.storage.StorageManager;
import android.os.storage.StorageVolume;
import android.text.InputType;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import java.io.BufferedReader;
import java.io.File;
import java.io.InputStreamReader;
import java.util.Arrays;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.Set;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public final class MainActivity extends Activity {
    private static final int ROOT = 1;
    private static final int PACKAGE = 2;
    private static final int MAX_OUTPUT = 512 * 1024;
    private static final Set<String> EXTERNAL_SHORTCUTS = new HashSet<>(Arrays.asList(
            "doctor", "ssh_start", "terminal", "nethunter"));

    private final ExecutorService executor = Executors.newSingleThreadExecutor();
    private final Map<String, Action> actions = new LinkedHashMap<>();
    private TextView output;
    private TextView status;

    private static final class Action {
        final String id;
        final String title;
        final String subtitle;
        final String value;
        final String confirmation;
        final int kind;
        final boolean danger;

        Action(String id, String title, String subtitle, String value,
               String confirmation, int kind, boolean danger) {
            this.id = id;
            this.title = title;
            this.subtitle = subtitle;
            this.value = value;
            this.confirmation = confirmation;
            this.kind = kind;
            this.danger = danger;
        }
    }

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        registerActions();
        buildInterface();

        String requested = getIntent().getStringExtra("action_id");
        if ("dev.duotechnician.toolbox.RUN".equals(getIntent().getAction())
                && EXTERNAL_SHORTCUTS.contains(requested) && actions.containsKey(requested)) {
            output.postDelayed(() -> dispatch(actions.get(requested)), 250);
        }
    }

    private void registerActions() {
        root("doctor", "System doctor", "Kernel, radios, USB, Kali, power and services",
                "/system/bin/duo-doctor", null, false);
        root("integrity", "Verify toolkit", "Check every kernel and injection-module hash",
                "/system/bin/duo-modprobe verify", null, false);
        root("kali_verify", "Verify Kali", "Package database and essential tool audit",
                "/system/bin/duo-kali verify", null, false);
        root("module_status", "Module status", "Show active technician modules",
                "/system/bin/duo-modprobe status", null, false);

        root("ssh_start", "Start Kali SSH", "Generate host keys if needed and start sshd",
                "/system/bin/duo-kali ssh start", null, false);
        root("ssh_stop", "Stop Kali SSH", "Stop only the chroot SSH daemon",
                "/system/bin/duo-kali ssh stop", "Stop the Kali SSH server?", false);
        root("kex_start", "Start KeX desktop", "Start the Kali graphical desktop server",
                "/system/bin/duo-kali kex start", null, false);
        root("kex_stop", "Stop KeX desktop", "Stop the Kali graphical desktop server",
                "/system/bin/duo-kali kex stop", "Stop the KeX desktop?", false);

        root("load_wifi", "Load external Wi-Fi", "Monitor-mode USB adapter drivers",
                "/system/bin/duo-modprobe wifi", null, false);
        root("load_bluetooth", "Load Bluetooth Arsenal", "USB, UART and virtual HCI transports",
                "/system/bin/duo-modprobe bluetooth", null, false);
        root("load_sdr", "Load SDR", "RTL-SDR, Airspy, HackRF and MSI2500 drivers",
                "/system/bin/duo-modprobe sdr", null, false);
        root("load_can", "Load CAN / CARsenal", "SocketCAN plus common USB CAN adapters",
                "/system/bin/duo-modprobe can", null, false);
        root("load_serial", "Load serial tools", "Embedded consoles and modem adapters",
                "/system/bin/duo-modprobe serial", null, false);
        root("load_network", "Load USB networking", "Ethernet, EEM, MBIM, QMI and RNDIS host",
                "/system/bin/duo-modprobe network", null, false);
        root("load_storage", "Load local storage", "UAS and field filesystem drivers",
                "/system/bin/duo-modprobe storage", null, false);
        root("load_remote", "Load remote storage", "NBD, NFS, CIFS and iSCSI",
                "/system/bin/duo-modprobe remote", null, false);
        root("load_usbip", "Load USB/IP", "USB/IP host and virtual controller",
                "/system/bin/duo-modprobe usbip", null, false);
        root("load_lab", "Load network lab", "VXLAN, GRE, IPIP, ipset and fq_codel",
                "/system/bin/duo-modprobe lab", null, false);

        root("inject_test", "Injection self-test", "One harmless wildcard broadcast probe",
                "/system/bin/duo-wifi test",
                "Authorized use only. Send one broadcast probe on the current monitor interface?",
                true);
        root("wifi_normal", "Restore managed Wi-Fi", "Clean reboot back to Android's stock WLAN",
                "/system/bin/duo-wifi normal",
                "This may immediately reboot the Duo to restore managed Wi-Fi. Continue?", true);
        root("hid_enable", "Enable USB keyboard + mouse", "Isolated HID gadget; restore ADB after two minutes",
                "/system/bin/duo-hid enable 120",
                "ADB will disconnect for up to two minutes while the Duo acts as a keyboard and mouse. Continue?",
                true);
        root("hid_left", "Mouse left click", "Send one left-button click to the authorized host",
                "/system/bin/duo-hid mouse click left", null, true);
        root("hid_right", "Mouse right click", "Send one right-button click to the authorized host",
                "/system/bin/duo-hid mouse click right", null, true);
        root("hid_move_left", "Mouse move left", "Move the host pointer 24 pixels left",
                "/system/bin/duo-hid mouse move -24 0", null, true);
        root("hid_move_right", "Mouse move right", "Move the host pointer 24 pixels right",
                "/system/bin/duo-hid mouse move 24 0", null, true);
        root("hid_move_up", "Mouse move up", "Move the host pointer 24 pixels up",
                "/system/bin/duo-hid mouse move 0 -24", null, true);
        root("hid_move_down", "Mouse move down", "Move the host pointer 24 pixels down",
                "/system/bin/duo-hid mouse move 0 24", null, true);
        root("hid_disable", "Restore Android USB from HID", "Stop HID now and restore ADB",
                "/system/bin/duo-hid disable", null, false);
        root("usb_status", "USB utility status", "Android, HID and isolated utility gadget ownership",
                "/system/bin/duo-usb status", null, false);
        root("usb_rndis", "USB network + SSH (Windows)", "RNDIS, DHCP and Kali SSH at 169.254.55.1",
                "/system/bin/duo-usb enable rndis 300",
                "ADB will disconnect for up to five minutes. The host should receive 169.254.55.10-20 by DHCP. Continue?",
                true);
        root("usb_ecm", "USB network + SSH (Linux/macOS)", "CDC ECM, DHCP and Kali SSH at 169.254.55.1",
                "/system/bin/duo-usb enable ecm 300",
                "ADB will disconnect for up to five minutes. The host should receive 169.254.55.10-20 by DHCP. Continue?",
                true);
        root("usb_acm", "USB serial transport", "CDC ACM transport; no unauthenticated login daemon",
                "/system/bin/duo-usb enable acm 60",
                "ADB will disconnect for up to 60 seconds while CDC ACM is active. Continue?", true);
        root("usb_midi", "USB MIDI", "Present the Duo as a standards-based MIDI device",
                "/system/bin/duo-usb enable midi 60",
                "ADB will disconnect for up to 60 seconds while USB MIDI is active. Continue?", true);
        root("usb_uac2", "USB Audio Class 2", "Present the Duo as a UAC2 audio device",
                "/system/bin/duo-usb enable uac2 60",
                "ADB will disconnect for up to 60 seconds while USB audio is active. Continue?", true);
        root("usb_disable", "Restore Android USB", "Stop the isolated utility profile and restore ADB",
                "/system/bin/duo-usb disable", null, false);
        root("bootloader", "Reboot to bootloader", "Enter the Duo boot selection screen",
                "reboot bootloader", "Reboot into the bootloader now?", true);

        app("terminal", "Open Kali terminal", "NetHunter Terminal sessions", "com.offsec.nhterm");
        app("nethunter", "Open NetHunter", "NetHunter control center", "com.offsec.nethunter");
        app("kex", "Open KeX client", "Connect to the graphical Kali desktop", "com.offsec.nethunter.kex");
        app("store", "Open NetHunter Store", "Install and update approved tools", "com.offsec.nethunter.store");
    }

    private void root(String id, String title, String subtitle, String command,
                      String confirmation, boolean danger) {
        actions.put(id, new Action(id, title, subtitle, command, confirmation, ROOT, danger));
    }

    private void app(String id, String title, String subtitle, String packageName) {
        actions.put(id, new Action(id, title, subtitle, packageName, null, PACKAGE, false));
    }

    private void buildInterface() {
        int page = getColor(R.color.navy);
        LinearLayout root = new LinearLayout(this);
        boolean wide = getResources().getConfiguration().screenWidthDp >= 720;
        root.setOrientation(wide ? LinearLayout.HORIZONTAL : LinearLayout.VERTICAL);
        root.setBackgroundColor(page);
        root.setPadding(dp(12), dp(12), dp(12), dp(12));

        LinearLayout actionColumn = new LinearLayout(this);
        actionColumn.setOrientation(LinearLayout.VERTICAL);
        actionColumn.addView(title("DUO TECHNICIAN", 24, getColor(R.color.cyan)));
        status = title(statusLine(), 13, getColor(R.color.text_secondary));
        status.setPadding(0, dp(2), 0, dp(12));
        actionColumn.addView(status);

        addSection(actionColumn, "Health and Kali");
        add(actionColumn, "doctor");
        add(actionColumn, "integrity");
        add(actionColumn, "kali_verify");
        add(actionColumn, "module_status");
        addSection(actionColumn, "Remote access and apps");
        add(actionColumn, "ssh_start");
        add(actionColumn, "ssh_stop");
        add(actionColumn, "kex_start");
        add(actionColumn, "kex_stop");
        add(actionColumn, "terminal");
        add(actionColumn, "nethunter");
        add(actionColumn, "kex");
        add(actionColumn, "store");
        addSection(actionColumn, "Field hardware");
        for (String id : new String[]{"load_wifi", "load_bluetooth", "load_sdr", "load_can",
                "load_serial", "load_network", "load_storage", "load_remote", "load_usbip", "load_lab"}) {
            add(actionColumn, id);
        }
        addSection(actionColumn, "Internal radio and USB gadget");
        addSpecial(actionColumn, "Internal Wi-Fi monitor", "Choose a channel and switch the Qualcomm radio",
                true, v -> promptMonitorChannel());
        add(actionColumn, "inject_test");
        add(actionColumn, "wifi_normal");
        add(actionColumn, "hid_enable");
        addSpecial(actionColumn, "Type through USB HID", "Send text after the keyboard gadget is active",
                true, v -> promptHidText());
        addSpecial(actionColumn, "Send a keyboard shortcut", "Examples: CTRL+ALT+T, GUI+R, CTRL+C",
                true, v -> promptHidKey());
        add(actionColumn, "hid_move_up");
        add(actionColumn, "hid_move_down");
        add(actionColumn, "hid_move_left");
        add(actionColumn, "hid_move_right");
        add(actionColumn, "hid_left");
        add(actionColumn, "hid_right");
        add(actionColumn, "hid_disable");
        add(actionColumn, "usb_status");
        add(actionColumn, "usb_rndis");
        add(actionColumn, "usb_ecm");
        add(actionColumn, "usb_acm");
        addSpecial(actionColumn, "Read-only USB disk", "Export a regular image file; block devices are forbidden",
                true, v -> promptMassStorage());
        add(actionColumn, "usb_midi");
        add(actionColumn, "usb_uac2");
        add(actionColumn, "usb_disable");
        add(actionColumn, "bootloader");

        ScrollView actionScroll = new ScrollView(this);
        actionScroll.setFillViewport(true);
        actionScroll.addView(actionColumn,
                new ScrollView.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));

        LinearLayout console = new LinearLayout(this);
        console.setOrientation(LinearLayout.VERTICAL);
        console.setPadding(wide ? dp(16) : 0, wide ? 0 : dp(12), 0, 0);
        TextView consoleTitle = title("COMMAND OUTPUT", 15, getColor(R.color.green));
        console.addView(consoleTitle);
        output = title("Ready. Root is requested only when an action needs it.", 14,
                getColor(R.color.text_primary));
        output.setTypeface(Typeface.MONOSPACE);
        output.setTextIsSelectable(true);
        output.setPadding(dp(12), dp(12), dp(12), dp(12));
        output.setBackgroundColor(getColor(R.color.panel));
        ScrollView outputScroll = new ScrollView(this);
        outputScroll.setFillViewport(true);
        outputScroll.addView(output,
                new ScrollView.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        console.addView(outputScroll,
                new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));

        if (wide) {
            root.addView(actionScroll, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, 1f));
            root.addView(console, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, 1f));
        } else {
            root.addView(actionScroll, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 3f));
            root.addView(console, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 2f));
        }
        setContentView(root);
    }

    private String statusLine() {
        boolean toolkit = new File("/system/bin/duo-doctor").canExecute();
        return "Android " + Build.VERSION.RELEASE + "  |  " + Build.MODEL
                + "  |  Toolkit " + (toolkit ? "detected" : "not installed");
    }

    private TextView title(String text, int sizeSp, int color) {
        TextView view = new TextView(this);
        view.setText(text);
        view.setTextSize(sizeSp);
        view.setTextColor(color);
        return view;
    }

    private void addSection(LinearLayout parent, String text) {
        TextView section = title(text.toUpperCase(Locale.ROOT), 13, getColor(R.color.green));
        section.setTypeface(Typeface.DEFAULT_BOLD);
        section.setPadding(dp(2), dp(16), dp(2), dp(5));
        parent.addView(section);
    }

    private void add(LinearLayout parent, String id) {
        Action action = actions.get(id);
        addSpecial(parent, action.title, action.subtitle, action.danger, v -> dispatch(action));
    }

    private void addSpecial(LinearLayout parent, String label, String subtitle,
                            boolean danger, View.OnClickListener listener) {
        Button button = new Button(this);
        button.setAllCaps(false);
        button.setGravity(Gravity.START | Gravity.CENTER_VERTICAL);
        button.setText(getString(R.string.button_label, label, subtitle));
        button.setTextSize(14);
        button.setTextColor(getColor(R.color.text_primary));
        button.setBackgroundTintList(ColorStateList.valueOf(
                danger ? getColor(R.color.danger) : getColor(R.color.panel)));
        button.setPadding(dp(14), dp(9), dp(14), dp(9));
        button.setOnClickListener(listener);
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        params.setMargins(0, dp(3), 0, dp(3));
        parent.addView(button, params);
    }

    private void dispatch(Action action) {
        if (action.kind == PACKAGE) {
            launchPackage(action.value);
            return;
        }
        if (action.confirmation != null) {
            new AlertDialog.Builder(this)
                    .setTitle(action.title)
                    .setMessage(action.confirmation)
                    .setNegativeButton("Cancel", null)
                    .setPositiveButton("Continue", (dialog, which) -> runRoot(action.title, action.value))
                    .show();
        } else {
            runRoot(action.title, action.value);
        }
    }

    private void promptMonitorChannel() {
        EditText input = new EditText(this);
        input.setInputType(InputType.TYPE_CLASS_NUMBER);
        input.setText("1");
        input.setSelectAllOnFocus(true);
        new AlertDialog.Builder(this)
                .setTitle("Internal monitor mode")
                .setMessage("Authorized use only. Android managed Wi-Fi will stop until a clean reboot.")
                .setView(input)
                .setNegativeButton("Cancel", null)
                .setPositiveButton("Enable", (dialog, which) -> {
                    String channel = input.getText().toString().trim();
                    if (!channel.matches("[0-9]{1,3}")) {
                        toast("Invalid channel");
                        return;
                    }
                    runRoot("Internal Wi-Fi monitor", "/system/bin/duo-wifi monitor " + channel);
                })
                .show();
    }

    private void promptHidText() {
        EditText input = new EditText(this);
        input.setSingleLine(false);
        input.setHint("Text to type");
        new AlertDialog.Builder(this)
                .setTitle("USB HID typing")
                .setMessage("Focus the destination field on the authorized host before continuing.")
                .setView(input)
                .setNegativeButton("Cancel", null)
                .setPositiveButton("Type", (dialog, which) -> {
                    String value = input.getText().toString();
                    if (value.isEmpty()) return;
                    runRoot("USB HID typing", "/system/bin/duo-hid type " + shellQuote(value));
                })
                .show();
    }

    private void promptHidKey() {
        EditText input = new EditText(this);
        input.setSingleLine(true);
        input.setHint("CTRL+ALT+T");
        new AlertDialog.Builder(this)
                .setTitle("USB HID shortcut")
                .setMessage("Focus the destination on the authorized host, then enter one named key combination.")
                .setView(input)
                .setNegativeButton("Cancel", null)
                .setPositiveButton("Send", (dialog, which) -> {
                    String value = input.getText().toString().trim();
                    if (!value.matches("[A-Za-z0-9+_-]{1,64}")) {
                        toast("Invalid key-combination format");
                        return;
                    }
                    runRoot("USB HID shortcut", "/system/bin/duo-hid key " + shellQuote(value));
                })
                .show();
    }

    private void promptMassStorage() {
        EditText input = new EditText(this);
        input.setSingleLine(true);
        String hint = "Absolute path to technician-disk.img";
        StorageManager storage = getSystemService(StorageManager.class);
        if (storage != null) {
            for (StorageVolume volume : storage.getStorageVolumes()) {
                File directory = volume.getDirectory();
                if (volume.isPrimary() && directory != null) {
                    hint = new File(new File(directory, "Download"),
                            "technician-disk.img").getPath();
                    break;
                }
            }
        }
        input.setHint(hint);
        new AlertDialog.Builder(this)
                .setTitle("Read-only USB disk")
                .setMessage("Choose an absolute path to a regular image file. ADB will restore automatically after 60 seconds.")
                .setView(input)
                .setNegativeButton("Cancel", null)
                .setPositiveButton("Export", (dialog, which) -> {
                    String value = input.getText().toString().trim();
                    if (!value.startsWith("/") || value.startsWith("/dev/")) {
                        toast("Use an absolute regular-file path, never /dev");
                        return;
                    }
                    runRoot("Read-only USB disk", "/system/bin/duo-usb enable mass 60 "
                            + shellQuote(value));
                })
                .show();
    }

    private static String shellQuote(String value) {
        return "'" + value.replace("'", "'\\''") + "'";
    }

    private void launchPackage(String packageName) {
        Intent launch = getPackageManager().getLaunchIntentForPackage(packageName);
        if (launch == null) {
            toast("App is not installed: " + packageName);
            return;
        }
        try {
            startActivity(launch);
        } catch (ActivityNotFoundException error) {
            toast("Could not open " + packageName);
        }
    }

    private void runRoot(String label, String command) {
        output.setText(getString(R.string.command_waiting, command));
        executor.submit(() -> {
            StringBuilder text = new StringBuilder();
            int exitCode = -1;
            try {
                Process process = new ProcessBuilder("su", "-c", command)
                        .redirectErrorStream(true).start();
                try (BufferedReader reader = new BufferedReader(
                        new InputStreamReader(process.getInputStream()))) {
                    String line;
                    while ((line = reader.readLine()) != null) {
                        if (text.length() < MAX_OUTPUT) text.append(line).append('\n');
                    }
                }
                exitCode = process.waitFor();
            } catch (Exception error) {
                text.append(error.getClass().getSimpleName()).append(": ")
                        .append(error.getMessage()).append('\n');
            }
            final int result = exitCode;
            final String captured = text.length() == 0 ? "(no output)\n" : text.toString();
            runOnUiThread(() -> {
                output.setText(getString(R.string.command_result, command, captured, result));
                status.setText(getString(R.string.status_last, statusLine(), label));
            });
        });
    }

    private void toast(String message) {
        Toast.makeText(this, message, Toast.LENGTH_LONG).show();
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }

    @Override
    protected void onDestroy() {
        executor.shutdownNow();
        super.onDestroy();
    }
}

