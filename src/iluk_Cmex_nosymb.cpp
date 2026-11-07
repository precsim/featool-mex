#include "mex.h"
#include "src_dep/iluk_helper.h"
#include <algorithm>
#include <ctime>
#include <vector>

#define ENABLE_PROFILE
#undef ENABLE_PROFILE

using std::binary_search;
using std::vector;

/***************************************************************************
 * File: iluk_Cmex_nosymb.c
 * Author: Killian Miller
 * Copyright (c) 2014 Killian Miller. All rights reserved.
 *
 * [L, U] = iluk_Cmex_nosymb(A, Lvl);
 *
 * Input:
 *         A     Sparse N by N matrix
 *         Lvl   Sparse N by N matrix with levels of permitted fill-ins
 *               Note that Lvl should be the level matrix for the transposed
 *               input matrix A.
 * Output:
 *         L     Sparse N by N lower triangular factor
 *         U     Sparse N by N upper triangular factor
 *
 * Computes an Incomplete LU factorization of the matrix A with level of
 * fill given by lfil. Note that A must be the transpose of the matrix for
 * which you want the ILU(k) factorization. The matrix Lvl MUST HAVE BEEN
 * RETURNED by an earlier call to iluk_Cmex.c. The algorithm uses the
 * Lvl data structure instead of performing a symbolic factorization.
 * The numeric values of permitted fill-in entries are computed and the L
 * and U factors are constructed. Note that you cannot output the sparse
 * array of levels as you already have that information.
 ***************************************************************************/
void mexFunction(int nlhs, mxArray *plhs[], int nrhs, const mxArray *prhs[])
{
        /*
         *  declare work variables
         */
        mwSize N, nnzU, nnzL, nnzLold, nnzUold;
        static const int realloc_thresh = 0;
        // N is the order of the matrix A
        // realloc_thresh (>= 0) is a constant that causes reallocation of
        // of the L and U factors if nzmax(.) - nnz(.) > realloc_thresh

        /*
         *  declare variables for sparse matrix A
         */
        double *A;
        mwIndex *prowA, *pcolindexA;

        /*
         *  declare variables for sparse matrix Lvl
         */
        double *Lvl;
        mwIndex *prowLvl, *pcolindexLvl;

    /*
         *  declare variables for output
         */
    mwIndex *prowL, *pcolindexL, *prowU, *pcolindexU;
        double *L, *U;

    // check input and output
        if (nrhs != 2) {
           mexErrMsgTxt("Two input arguments required");
        }
        if (nlhs != 2) {
           mexErrMsgTxt("Only two outputs");
        }

    // sparse matrix A
        if (!(mxIsSparse(prhs[0])) || !(mxIsDouble(prhs[0])) ||
                mxIsComplex(prhs[0]) || mxIsEmpty(prhs[0])) {
        mexErrMsgTxt("Input matrix must be nonempty, real, sparse, and double");
        }
        A = mxGetPr(prhs[0]);              // real vector for A
        prowA = mxGetIr(prhs[0]);          // row indices for elements of A
        pcolindexA = mxGetJc(prhs[0]); // index into the columns
        N = mxGetN(prhs[0]);           // number of columns of A
        if(N != mxGetM(prhs[0])) {
                mexErrMsgTxt("Input matrix must be square");
        }

        // sparse matrix Lvl
        if (!(mxIsSparse(prhs[1])) || !(mxIsDouble(prhs[1])) ||
                mxIsComplex(prhs[1]) || mxIsEmpty(prhs[1])) {
        mexErrMsgTxt("Input matrix of levels must be nonempty, real, sparse, and double");
        }
        Lvl = mxGetPr(prhs[1]);
        prowLvl = mxGetIr(prhs[1]);        // row indices for elements of A
        pcolindexLvl = mxGetJc(prhs[1]); // index into the columns
        if(mxGetN(prhs[1]) != N || N != mxGetM(prhs[1])) {
                mexErrMsgTxt("Input matrix must be square and of order N");
        }

        // A level matrix returned by iluk_Cmex stores original A entries at shifted
        // level 1 and generated fill entries at levels >= 2.  Reuse is valid only
        // when the current A sparsity pattern exactly matches those level-1 entries.
        // This also guarantees that capacities derived from Lvl are sufficient for A.
        for(mwIndex j = 0; j != N; ++j) {
                mwIndex a = pcolindexA[j];
                mwIndex a_end = pcolindexA[j + 1];
                mwIndex lvl = pcolindexLvl[j];
                mwIndex lvl_end = pcolindexLvl[j + 1];

                while(a < a_end || lvl < lvl_end) {
                        while(lvl < lvl_end && Lvl[lvl] != 1.0) {
                                ++lvl;
                        }
                        if(a == a_end) {
                                if(lvl != lvl_end) {
                                        mexErrMsgTxt("Level-1 pattern must match the sparsity pattern of A");
                                }
                                break;
                        }
                        if(lvl == lvl_end || prowLvl[lvl] != prowA[a]) {
                                mexErrMsgTxt("Level-1 pattern must match the sparsity pattern of A");
                        }
                        ++a;
                        ++lvl;
                }
        }

        // count the number of nonzeros in L and U
        nnzL = 0;
        for(mwIndex i = 1; i != N; ++i) {
                mwIndex j = pcolindexLvl[i];
                while(j < pcolindexLvl[i + 1] && prowLvl[j] < i) {
                        ++j;
                }
                nnzL += (j - pcolindexLvl[i]);
        }
        nnzU = pcolindexLvl[N] - nnzL;
        nnzL += N;

        // create output matrices
        plhs[0] = mxCreateSparse(N, N, nnzL, mxREAL);
        L = mxGetPr(plhs[0]);
        prowL = mxGetIr(plhs[0]);
        pcolindexL = mxGetJc(plhs[0]);

        plhs[1] = mxCreateSparse(N, N, nnzU, mxREAL);
        U = mxGetPr(plhs[1]);
        prowU = mxGetIr(plhs[1]);
        pcolindexU = mxGetJc(plhs[1]);

        // first rows of L and U are known
        pcolindexU[0] = 0;
        pcolindexU[1] = pcolindexA[1];
        for(mwIndex j = pcolindexA[0]; j != pcolindexA[1]; ++j) {
                prowU[j] = prowA[j];
                U[j] = A[j];
        }
        // check that first nonzero in first row of U is a diagonal element
        if(pcolindexU[0] == pcolindexU[1] || prowU[pcolindexU[0]] != 0 ||
                U[pcolindexU[0]] == 0.0) {
                mexErrMsgTxt("U has zero diagonal element");
        }
        pcolindexL[0] = 0;
        pcolindexL[1] = 1;
        prowL[0] = 0;
        L[0] = 1.0;

        // numeric phase
        // compute the values of permitted fill-in entries and build L and U
        #ifdef ENABLE_PROFILE
        clock_t t_num = clock();
        #endif
        nnzLold = nnzL; nnzUold = nnzU;
        nnzL = 1; nnzU = pcolindexU[1];
        {
        vector<double> work(N, 0.0);
        vector<char> work_lev(N, 0); // work array for levels
        for(mwIndex j = 1; j != N; ++j) {
                // unpack jth row of A into the work array
                for(mwIndex k = pcolindexA[j]; k != pcolindexA[j + 1]; ++k) {
                        work[prowA[k]] = A[k];
                }
                // unpack jth row of level into a work array
                for(mwIndex k = pcolindexLvl[j]; k != pcolindexLvl[j + 1]; ++k) {
                        work_lev[prowLvl[k]] = 1;
                }
                mwIndex i = pcolindexLvl[j];
                while(i < pcolindexLvl[j + 1] && prowLvl[i] < j) {
                        mwIndex pivot_row = prowLvl[i];
                        mwIndex pivot_start = pcolindexU[pivot_row];
                        mwIndex pivot_end = pcolindexU[pivot_row + 1];
                        if(pivot_start == pivot_end || prowU[pivot_start] != pivot_row || U[pivot_start] == 0.0) {
                                mexErrMsgTxt("U has zero diagonal element");
                        }
                        double alpha = work[pivot_row] / U[pivot_start];
                        work[prowLvl[i]] = alpha;
                        for(mwIndex k = pcolindexU[prowLvl[i]] + 1; k != pcolindexU[prowLvl[i] + 1]; ++k) {
                                // is prowU[k] a permitted fill-in?
                                if(work_lev[prowU[k]] == 1) {
                                        work[prowU[k]] -= alpha * U[k];
                                }
                                // if memory is an issue you can avoid the work_lev array
                                // by using a binary search, however, doing so may
                                // significantly increase computing time, especially when
                                // the level of fill is large
                                //if(binary_search(prowLvl + pcolindexLvl[j], prowLvl + pcolindexLvl[j + 1], prowU[k])) {
                                //      work[prowU[k]] -= alpha * U[k];
                                //}
                        }
                        ++i;
                }
                // update row j of L and U and zero the work array
                for(mwIndex k = pcolindexLvl[j]; k != pcolindexLvl[j + 1]; ++k) {
                        if(work[prowLvl[k]] != 0.0) {
                                if(prowLvl[k] < j) {
                                        L[nnzL] = work[prowLvl[k]];
                                        prowL[nnzL++] = prowLvl[k];
                                }
                                else {
                                        U[nnzU] = work[prowLvl[k]];
                                        prowU[nnzU++] = prowLvl[k];
                                }
                                work[prowLvl[k]] = 0.0;
                        }
                        work_lev[prowLvl[k]] = 0;
                }
                pcolindexU[j + 1] = nnzU;
                // check that first nonzero in row j of U is a diagonal element
                if(pcolindexU[j] == pcolindexU[j + 1] || prowU[pcolindexU[j]] != j) {
                        mexErrMsgTxt("U has a zero diagonal element");
                }
                L[nnzL] = 1.0;
                prowL[nnzL++] = j;
                pcolindexL[j + 1] = nnzL;
        }
        } // artificial scope to force destruction of work object
        #ifdef ENABLE_PROFILE
        t_num = clock() - t_num;
        printf("Time for numeric factorization (sec): %f\n",static_cast<double>(t_num)/CLOCKS_PER_SEC);
        #endif

        // decrease the maximum number of nonzeros in L and U to nnzL and nnzU if necessary
        if(nnzLold - nnzL > realloc_thresh) {
                reallocNzmax(plhs[0], &L, &prowL, nnzL);
        }
        if(nnzUold - nnzU > realloc_thresh) {
                reallocNzmax(plhs[1], &U, &prowU, nnzU);
        }

        // transpose L and U to obtain CSC format for output
        sparse_sqr_transpose(L, prowL, pcolindexL, N);
        sparse_sqr_transpose(U, prowU, pcolindexU, N);
}
