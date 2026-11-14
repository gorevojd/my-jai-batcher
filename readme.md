# my-jai-batcher

Triangle batching for Jai, with CPU data preparation and an optional OpenGL backend.

## Dependencies

Direct module dependencies:

- [my-jai-math](https://github.com/gorevojd/my-jai-math): vectors, matrices and colors.

Jai standard library: `Basic`; `GL` only when `GRAPHICS_API = .OpenGL`.

The default `GRAPHICS_API = .None` needs no OpenGL context. The OpenGL backend
requires the application to provide an initialized OpenGL context and load GL
functions before using GPU operations.

## Import

```jai
B :: #import "my-jai-batcher";
```

Add the parent directories of this module and its dependencies to the compiler's
module search path. Install the dependencies' own dependencies as documented in
their READMEs.

When bundled in my-jai-core, initialize the checkout with
`git submodule update --init --recursive` and add the directory containing Core
and Core itself to the search path (`Src/Modules` and `Src/Modules/my-jai-core`
in PacCodex).

Select the OpenGL backend at the executable entry point:

```jai
B :: #import "my-jai-batcher"()(GRAPHICS_API = .OpenGL);
```
