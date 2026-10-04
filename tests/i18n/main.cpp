// Translation test: with LANGUAGE=de and a throwaway atlas-ui_de.qm in
// ATLAS_UI_TRANSLATIONS_DIR (both set by ctest), a default SearchField must
// show the German placeholder. Guards the loader (ui/translations.cpp) and the
// engine refresh (ui/atlasuiplugin.cpp). See tests/README.md.
#include <QtQuickTest/quicktest.h>

QUICK_TEST_MAIN(atlas_i18n)
