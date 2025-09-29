#include "SinbadExample.hpp"

int main(int argc, char* argv[]){
    (void)argc;
    (void)argv;
    SinbadExample app;
    app.initApp();
    app.getRoot()->startRendering();
    app.closeApp();
    return 0;
}