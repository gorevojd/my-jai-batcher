#module_parameters () (GRAPHICS_APIS := (#import "MyBasic").GraphicsApi.None);

#scope_module
#import "Basic";
#import "MyMath";

#scope_export
#load "batcher.jai";

#if (GRAPHICS_APIS & .OpenGL) != .None {
    #scope_module
    #import "GL";

    #scope_export
    #load "batcher_ogl.jai";
}
