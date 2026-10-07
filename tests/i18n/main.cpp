// Translation test: with LANGUAGE=de and a throwaway telamon-ui_de.qm in
// TELAMON_UI_TRANSLATIONS_DIR (both set by ctest), a default SearchField must
// show the German placeholder. Guards the loader (ui/translations.cpp) and the
// engine refresh (ui/telamonuiplugin.cpp). See tests/README.md.
#include <QtQuickTest/quicktest.h>

QUICK_TEST_MAIN(telamon_i18n)
