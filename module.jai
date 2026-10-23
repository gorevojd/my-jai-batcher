#module_parameters () (IMPORT_OGL_IMPLEMENTATION := false);

#scope_module
#import "Basic";
#import "MyMath";

#scope_export
#load "batcher.jai";
#load "batcher_color_glsl.jai";

#if IMPORT_OGL_IMPLEMENTATION {
    #scope_module
    #import "GL";

    #scope_export
    #load "batcher_ogl.jai";
}
