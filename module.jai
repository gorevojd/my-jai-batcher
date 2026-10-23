#module_parameters () (IMPORT_OGL_IMPLEMENTATION := false);

#scope_module
#import "Basic";
#import "MyMath";
#import "MyAssets";
#import "MyLocalization";

#scope_export
#load "batcher.jai";
#load "batcher_fonts.jai";

#if IMPORT_OGL_IMPLEMENTATION {
    #scope_module
    #import "GL";

    #scope_export
    #load "batcher_ogl.jai";
}
