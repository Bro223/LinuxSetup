#include <gtk/gtk.h>
#include <gtk4-layer-shell.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <time.h>

// -------- Helper Functions --------
static gchar *read_command_output(const char *cmd) {
    gchar buffer[256];
    GString *result = g_string_new(NULL);
    FILE *pipe = popen(cmd, "r");
    if (!pipe) return g_strdup("N/A");
    while (fgets(buffer, sizeof(buffer), pipe) != NULL) {
        g_string_append(result, buffer);
    }
    pclose(pipe);
    return g_string_free(result, FALSE);
}

static gchar *get_cpu_usage() {
    FILE *fp = fopen("/proc/stat", "r");
    if (!fp) return g_strdup("N/A");
    unsigned long long user1, nice1, system1, idle1, iowait1, irq1, softirq1, steal1;
    fscanf(fp, "cpu %llu %llu %llu %llu %llu %llu %llu %llu",
           &user1, &nice1, &system1, &idle1, &iowait1, &irq1, &softirq1, &steal1);
    fclose(fp);

    g_usleep(100000); // 100ms

    fp = fopen("/proc/stat", "r");
    if (!fp) return g_strdup("N/A");
    unsigned long long user2, nice2, system2, idle2, iowait2, irq2, softirq2, steal2;
    fscanf(fp, "cpu %llu %llu %llu %llu %llu %llu %llu %llu",
           &user2, &nice2, &system2, &idle2, &iowait2, &irq2, &softirq2, &steal2);
    fclose(fp);

    unsigned long long idle = idle2 + iowait2 - idle1 - iowait1;
    unsigned long long non_idle = (user2 + nice2 + system2 + irq2 + softirq2 + steal2) -
    (user1 + nice1 + system1 + irq1 + softirq1 + steal1);
    unsigned long long total = idle + non_idle;
    if (total == 0) return g_strdup("N/A");
    double cpu_percent = (double)non_idle * 100.0 / total;
    return g_strdup_printf("%.1f%%", cpu_percent);
}

static gchar *get_ram_usage() {
    FILE *fp = fopen("/proc/meminfo", "r");
    if (!fp) return g_strdup("N/A");
    unsigned long mem_total = 0, mem_available = 0;
    char line[256];
    while (fgets(line, sizeof(line), fp)) {
        if (sscanf(line, "MemTotal: %lu kB", &mem_total) == 1) continue;
        if (sscanf(line, "MemAvailable: %lu kB", &mem_available) == 1) break;
    }
    fclose(fp);
    if (mem_total == 0) return g_strdup("N/A");
    unsigned long mem_used = mem_total - mem_available;
    unsigned int mem_perc = (unsigned int)(mem_used * 100 / mem_total);
    return g_strdup_printf("%lukB / %lukB (%u%%)", mem_used, mem_total, mem_perc);
}

static gchar *get_nvidia_gpu_usage() {
    if (system("command -v nvidia-smi > /dev/null") == 0) {
        gchar *output = read_command_output("nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits");
        gchar *newline = strchr(output, '\n');
        if (newline) *newline = 0;
        return output;
    }
    return g_strdup("N/A");
}

static gchar *get_intel_gpu_usage() {
    if (system("command -v intel_gpu_top > /dev/null") == 0) {
        gchar *output = read_command_output("timeout 1s sudo intel_gpu_top -o - -s 1000 | awk 'NR==3 { print $9 }'");
        gchar *newline = strchr(output, '\n');
        if (newline) *newline = 0;
        return output;
    }
    return g_strdup("N/A");
}

static gchar *get_gpu_in_use() {
    gchar *output = read_command_output("glxinfo 2>/dev/null | grep \"OpenGL renderer\" | sed -e 's/OpenGL renderer string: //' | head -n1");
    if (strlen(output) == 0) {
        g_free(output);
        return g_strdup("N/A");
    }
    gchar *newline = strchr(output, '\n');
    if (newline) *newline = 0;
    return output;
}

static gchar *get_wm() {
    const char* wm = g_getenv("XDG_SESSION_TYPE");
    if (!wm || strlen(wm) == 0) return g_strdup("N/A");
    return g_strdup(wm);
}

static gchar *get_time() {
    time_t rawtime;
    struct tm *timeinfo;
    char buffer[64];
    time(&rawtime);
    timeinfo = localtime(&rawtime);
    strftime(buffer, sizeof(buffer), "%Y-%m-%d %H:%M:%S", timeinfo);
    return g_strdup(buffer);
}

// -------- Global Labels --------
static GPtrArray *labels;

// -------- Update Stats --------
static gboolean update_stats(gpointer user_data) {
    gchar text[1024];
    gchar *cpu = get_cpu_usage();
    gchar *ram = get_ram_usage();

    static gchar *nvidia = NULL;
    static gchar *intel = NULL;
    static time_t last_gpu_check = 0;
    time_t now = time(NULL);

    if (now - last_gpu_check >= 5) {
        if (nvidia) g_free(nvidia);
        if (intel) g_free(intel);
        nvidia = get_nvidia_gpu_usage();
        intel  = get_intel_gpu_usage();
        last_gpu_check = now;
    }

    static gchar *gpu_in_use = NULL;
    if (!gpu_in_use) gpu_in_use = get_gpu_in_use();

    static gchar *wm = NULL;
    if (!wm) wm = get_wm();

    gchar *time_str = get_time();

    snprintf(text, sizeof(text),
             "╔═════════════════════════════════════════╗\n"
             "CPU Usage: %s\n"
             "RAM Usage: %s\n"
             "Nvidia GPU Usage: %s%%\n"
             "Intel GPU Usage: %s%%\n"
             "=>%s\n"
             "WM / Display Server: %s\n"
             "╚═════════════════════════════════════════╝\n"
             "%s\n",
             cpu, ram, nvidia, intel, gpu_in_use, wm, time_str);

    for (guint i = 0; i < labels->len; i++) {
        GtkWidget *label = g_ptr_array_index(labels, i);
        gtk_label_set_text(GTK_LABEL(label), text);
    }

    g_free(cpu);
    g_free(ram);
    g_free(time_str);

    return G_SOURCE_CONTINUE;
}

// -------- Create Window for Monitor --------
static GtkWidget* create_sysmon_window(GtkApplication *app, GdkMonitor *monitor) {
    GtkWindow *window = GTK_WINDOW(gtk_application_window_new(app));
    gtk_window_set_decorated(window, FALSE);
    gtk_window_set_default_size(window, 1, 1);

    gtk_layer_init_for_window(window);
    gtk_layer_set_layer(window, GTK_LAYER_SHELL_LAYER_BOTTOM);
    gtk_layer_set_monitor(window, monitor); // key line
    gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_TOP, TRUE);
    gtk_layer_set_anchor(window, GTK_LAYER_SHELL_EDGE_LEFT, TRUE);
    gtk_layer_set_margin(window, GTK_LAYER_SHELL_EDGE_TOP, 340);
    gtk_layer_set_margin(window, GTK_LAYER_SHELL_EDGE_LEFT, 650);

    GtkWidget *label = gtk_label_new(NULL);
    gtk_label_set_xalign(GTK_LABEL(label), 0);
    gtk_label_set_justify(GTK_LABEL(label), GTK_JUSTIFY_LEFT);
    gtk_window_set_child(window, label);

    // Click-through
    GdkSurface *surface = gtk_native_get_surface(GTK_NATIVE(window));
    gdk_surface_set_input_region(surface, NULL);

    // CSS
    GtkCssProvider *provider = gtk_css_provider_new();
    gtk_css_provider_load_from_string(provider,
                                      "window {"
                                      "   background-color: rgba(0,0,0,0.5);"
                                      "   color: #ffffff;"
                                      "   font-family: 'ProFontWindows';"
                                      "   font-size: 32px;"
                                      "   border: 2px solid #444444;"
                                      "   padding: 6px;"
                                      "   border-radius: 6px;"
                                      "}"
    );
    gtk_style_context_add_provider_for_display(
        gtk_widget_get_display(label),
                                               GTK_STYLE_PROVIDER(provider),
                                               GTK_STYLE_PROVIDER_PRIORITY_USER
    );

    gtk_widget_set_visible(GTK_WIDGET(window), TRUE);

    return label;
}

// -------- Activate --------
static void activate(GtkApplication *app, gpointer user_data) {
    labels = g_ptr_array_new_with_free_func(NULL);

    GdkDisplay *display = gdk_display_get_default();
    GListModel *monitors = gdk_display_get_monitors(display);
    guint n_monitors = g_list_model_get_n_items(monitors);

    for (guint i = 0; i < n_monitors; i++) {
        GdkMonitor *monitor = g_list_model_get_item(monitors, i);
        GtkWidget *label = create_sysmon_window(app, monitor);
        g_ptr_array_add(labels, label);
        g_object_unref(monitor); // must unref after g_list_model_get_item
    }

    g_timeout_add_seconds(1, update_stats, NULL);
    update_stats(NULL);
}

// -------- Main --------
int main(int argc, char **argv) {
    GtkApplication *app = gtk_application_new("com.example.sysmon", G_APPLICATION_DEFAULT_FLAGS);
    g_signal_connect(app, "activate", G_CALLBACK(activate), NULL);
    int status = g_application_run(G_APPLICATION(app), argc, argv);
    g_object_unref(app);
    return status;
}
