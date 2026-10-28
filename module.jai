#module_parameters () (GRAPHICS_API: enum {
                          None;
                          OpenGL;
                      } = .None);

#scope_module
#import "Basic";
#import "MyMath";

#scope_export
#load "batcher.jai";

#if GRAPHICS_API == .OpenGL {
    #scope_module
    #import "GL";

    #scope_export
    #load "batcher_ogl.jai";
}
