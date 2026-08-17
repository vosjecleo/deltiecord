#include "my_application.h"

#include <glib.h>
#include <sys/prctl.h>

int main(int argc, char** argv) {
  // Keep desktop integration on the reverse-DNS application id while making
  // process monitors display the human-readable application name.
  g_set_prgname("Deltiecord");
  prctl(PR_SET_NAME, "Deltiecord", 0, 0, 0);
  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
