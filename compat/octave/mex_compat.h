#ifndef FEATOOL_OCTAVE_MEX_COMPAT_H
#define FEATOOL_OCTAVE_MEX_COMPAT_H

/*
 * Compatibility declarations needed by the unchanged baseline source tree.
 * Include Octave's MEX API first, then supply MATLAB typedef spellings that
 * older Octave releases do not provide. string.h also declares memcpy used by
 * the original findsp.c source.
 */
#include "mex.h"
#include <stdint.h>
#include <string.h>

#define mxUint64 uint64_t
#define mxDouble double

#endif
