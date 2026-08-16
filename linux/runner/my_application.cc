#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  GtkWindow* window;
  gboolean remember_window_state;
  gboolean show_native_title_bar;
  gint window_x;
  gint window_y;
  gint window_width;
  gint window_height;
  gboolean maximized;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

static gchar* window_state_path() {
  gchar* directory =
      g_build_filename(g_get_user_config_dir(), "deltiecord", nullptr);
  g_mkdir_with_parents(directory, 0700);
  gchar* path = g_build_filename(directory, "window.ini", nullptr);
  g_free(directory);
  return path;
}

static void load_window_state(MyApplication* self) {
  g_autofree gchar* path = window_state_path();
  g_autoptr(GKeyFile) state = g_key_file_new();
  if (!g_key_file_load_from_file(state, path, G_KEY_FILE_NONE, nullptr)) return;
  if (g_key_file_has_key(state, "window", "remember", nullptr)) {
    self->remember_window_state =
        g_key_file_get_boolean(state, "window", "remember", nullptr);
  }
  if (g_key_file_has_key(state, "window", "native_title_bar", nullptr)) {
    self->show_native_title_bar =
        g_key_file_get_boolean(state, "window", "native_title_bar", nullptr);
  }
  if (!self->remember_window_state) return;
  self->window_width = g_key_file_get_integer(state, "window", "width", nullptr);
  self->window_height =
      g_key_file_get_integer(state, "window", "height", nullptr);
  self->window_x = g_key_file_get_integer(state, "window", "x", nullptr);
  self->window_y = g_key_file_get_integer(state, "window", "y", nullptr);
  self->maximized = g_key_file_get_boolean(state, "window", "maximized", nullptr);
}

static void save_window_state(MyApplication* self) {
  g_autoptr(GKeyFile) state = g_key_file_new();
  g_key_file_set_boolean(state, "window", "remember",
                         self->remember_window_state);
  g_key_file_set_boolean(state, "window", "native_title_bar",
                         self->show_native_title_bar);
  if (self->remember_window_state) {
    g_key_file_set_integer(state, "window", "width", self->window_width);
    g_key_file_set_integer(state, "window", "height", self->window_height);
    g_key_file_set_integer(state, "window", "x", self->window_x);
    g_key_file_set_integer(state, "window", "y", self->window_y);
    g_key_file_set_boolean(state, "window", "maximized", self->maximized);
  }
  gsize length = 0;
  g_autofree gchar* data = g_key_file_to_data(state, &length, nullptr);
  g_autofree gchar* path = window_state_path();
  g_file_set_contents(path, data, length, nullptr);
}

static gboolean window_configure_cb(GtkWidget*, GdkEventConfigure* event,
                                    MyApplication* self) {
  if (!self->remember_window_state || self->maximized) return FALSE;
  self->window_x = event->x;
  self->window_y = event->y;
  self->window_width = event->width;
  self->window_height = event->height;
  return FALSE;
}

static gboolean window_state_cb(GtkWidget*, GdkEventWindowState* event,
                                MyApplication* self) {
  self->maximized =
      (event->new_window_state & GDK_WINDOW_STATE_MAXIMIZED) != 0;
  return FALSE;
}

static void window_method_cb(FlMethodChannel* channel, FlMethodCall* call,
                             gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  if (strcmp(fl_method_call_get_name(call), "present") == 0) {
    if (self->window != nullptr) {
      gtk_widget_show(GTK_WIDGET(self->window));
      gtk_window_deiconify(self->window);
      gtk_window_present(self->window);
    }
    g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
        fl_method_success_response_new(nullptr));
    fl_method_call_respond(call, response, nullptr);
    return;
  }
  if (strcmp(fl_method_call_get_name(call), "configure") != 0) {
    fl_method_call_respond_not_implemented(call, nullptr);
    return;
  }
  FlValue* args = fl_method_call_get_args(call);
  FlValue* title = fl_value_lookup_string(args, "showNativeTitleBar");
  FlValue* remember = fl_value_lookup_string(args, "rememberWindowState");
  if (title != nullptr) self->show_native_title_bar = fl_value_get_bool(title);
  if (remember != nullptr)
    self->remember_window_state = fl_value_get_bool(remember);
  save_window_state(self);
  g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
      fl_method_success_response_new(nullptr));
  fl_method_call_respond(call, response, nullptr);
}

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));
  self->window = window;
  load_window_state(self);

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar && self->show_native_title_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "deltiecord");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else if (self->show_native_title_bar) {
    gtk_window_set_title(window, "deltiecord");
  } else {
    gtk_window_set_titlebar(window, nullptr);
    gtk_window_set_decorated(window, FALSE);
  }

  gtk_window_set_default_size(
      window, self->window_width > 0 ? self->window_width : 1280,
      self->window_height > 0 ? self->window_height : 720);
  if (self->remember_window_state && self->window_x >= 0 &&
      self->window_y >= 0) {
    gtk_window_move(window, self->window_x, self->window_y);
  }
  if (self->maximized) gtk_window_maximize(window);
  g_signal_connect(window, "configure-event", G_CALLBACK(window_configure_cb),
                   self);
  g_signal_connect(window, "window-state-event", G_CALLBACK(window_state_cb),
                   self);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "net.deltie.deltiecord/window", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, window_method_cb,
                                            g_object_ref(self), g_object_unref);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  save_window_state(self);

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {
  self->window = nullptr;
  self->remember_window_state = TRUE;
  self->show_native_title_bar = TRUE;
  self->window_x = -1;
  self->window_y = -1;
  self->window_width = 1280;
  self->window_height = 720;
  self->maximized = FALSE;
}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
