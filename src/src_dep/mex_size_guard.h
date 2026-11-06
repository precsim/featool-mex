#ifndef MEX_SIZE_GUARD_H_INCLUDED
#define MEX_SIZE_GUARD_H_INCLUDED

#include "mex.h"
#include <limits.h>
#include <math.h>

static void mexRequireIntAddressableInputs(int nrhs, const mxArray *prhs[])
{
    for (int arg = 0; arg < nrhs; ++arg) {
        if (mxGetNumberOfElements(prhs[arg]) > (mwSize)INT_MAX)
            mexErrMsgIdAndTxt("featool_mex:sizeOverflow",
                              "Input array exceeds the supported 32-bit element range.");

        const mwSize ndims = mxGetNumberOfDimensions(prhs[arg]);
        const mwSize *dims = mxGetDimensions(prhs[arg]);
        for (mwSize d = 0; d < ndims; ++d)
            if (dims[d] > (mwSize)INT_MAX)
                mexErrMsgIdAndTxt("featool_mex:sizeOverflow",
                                  "Input dimension exceeds the supported 32-bit index range.");
    }
}

static int mexCheckedSizeToInt(mwSize value, const char *name)
{
    if (value > (mwSize)INT_MAX)
        mexErrMsgIdAndTxt("featool_mex:sizeOverflow",
                          "%s exceeds the supported 32-bit index range.", name);
    return (int)value;
}

static int mexCheckedPositiveIntScalar(const mxArray *array, const char *name)
{
    const double value = mxGetScalar(array);
    if (!isfinite(value) || value < 1.0 || value > (double)INT_MAX ||
        value != floor(value))
        mexErrMsgIdAndTxt("featool_mex:sizeOverflow",
                          "%s must be a positive integer in the supported 32-bit range.", name);
    return (int)value;
}

static int mexCheckedMulInt(int a, int b, const char *name)
{
    if (a < 0 || b < 0 || (b != 0 && a > INT_MAX/b))
        mexErrMsgIdAndTxt("featool_mex:sizeOverflow",
                          "%s exceeds the supported 32-bit index range.", name);
    return a*b;
}

static int mexCheckedAddInt(int a, int b, const char *name)
{
    if (a < 0 || b < 0 || a > INT_MAX-b)
        mexErrMsgIdAndTxt("featool_mex:sizeOverflow",
                          "%s exceeds the supported 32-bit index range.", name);
    return a+b;
}

#endif
