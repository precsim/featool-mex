/*   This file is part of redbKIT.
 *   Copyright (c) 2016, Ecole Polytechnique Federale de Lausanne (EPFL)
 *   Author: Federico Negri <federico.negri@epfl.ch>
 */

#include "mex.h"
#include <stdio.h>
#include <math.h>
#include <string.h>
#define INVJAC(i,j,k) invjac[i+(j+k*dim)*noe]
#define GRADREFPHI(i,j,k) gradrefphi[i+(j+k*NumQuadPoints)*nln]

#include "src_dep/Tools.h"
#include "src_dep/mex_size_guard.h"
#include "src_dep/LinearElasticMaterial.h"
#include "src_dep/SEMMTMaterial.h"
#include "src_dep/NeoHookeanMaterial.h"
#include "src_dep/StVenantKirchhoffMaterial.h"
#include "src_dep/RaghavanVorpMaterial.h"

#ifdef _OPENMP
#include <omp.h>
#endif

/*************************************************************************/

void mexFunction(int nlhs, mxArray* plhs[], int nrhs, const mxArray* prhs[])
{

    enum {
        MODEL_LINEAR_FORCES,
        MODEL_LINEAR_JACOBIAN_SLOW,
        MODEL_LINEAR_JACOBIAN,
        MODEL_LINEAR_STRESS,
        MODEL_SEMMT_FORCES,
        MODEL_SEMMT_JACOBIAN_SLOW,
        MODEL_SEMMT_JACOBIAN,
        MODEL_STVENANTKIRCHHOFF_FORCES,
        MODEL_STVENANTKIRCHHOFF_JACOBIAN_SLOW,
        MODEL_STVENANTKIRCHHOFF_JACOBIAN,
        MODEL_STVENANTKIRCHHOFF_STRESS,
        MODEL_NEOHOOKEAN_FORCES,
        MODEL_NEOHOOKEAN_JACOBIAN,
        MODEL_NEOHOOKEAN_JACOBIAN_SLOW,
        MODEL_NEOHOOKEAN_STRESS,
        MODEL_NEOHOOKEAN_PRESTRESS,
        MODEL_RAGHAVANVORP_FORCES,
        MODEL_RAGHAVANVORP_JACOBIAN,
        MODEL_RAGHAVANVORP_JACOBIAN_SLOW,
        MODEL_RAGHAVANVORP_STRESS,
        MODEL_UNKNOWN
    } model = MODEL_UNKNOWN;
    int expected_nrhs = 11;
    int expected_nlhs = 0;

    if (nrhs < 2) {
        mexErrMsgTxt("At least two inputs are required.");
    }
    if (!mxIsChar(prhs[1])) {
        mexErrMsgTxt("Second input must be a material model name.");
    }

    char *Material_Model = mxArrayToString(prhs[1]);
    if (Material_Model == NULL) {
        mexErrMsgTxt("Could not read material model name.");
    }

    if (strcmp(Material_Model, "Linear_forces") == 0) {
        model = MODEL_LINEAR_FORCES;
        expected_nlhs = 2;
    } else if (strcmp(Material_Model, "Linear_jacobianSlow") == 0) {
        model = MODEL_LINEAR_JACOBIAN_SLOW;
        expected_nlhs = 3;
    } else if (strcmp(Material_Model, "Linear_jacobian") == 0) {
        model = MODEL_LINEAR_JACOBIAN;
        expected_nlhs = 3;
    } else if (strcmp(Material_Model, "Linear_stress") == 0) {
        model = MODEL_LINEAR_STRESS;
        expected_nlhs = 2;
    } else if (strcmp(Material_Model, "SEMMT_forces") == 0) {
        model = MODEL_SEMMT_FORCES;
        expected_nlhs = 2;
    } else if (strcmp(Material_Model, "SEMMT_jacobianSlow") == 0) {
        model = MODEL_SEMMT_JACOBIAN_SLOW;
        expected_nlhs = 3;
    } else if (strcmp(Material_Model, "SEMMT_jacobian") == 0) {
        model = MODEL_SEMMT_JACOBIAN;
        expected_nlhs = 3;
    } else if (strcmp(Material_Model, "StVenantKirchhoff_forces") == 0) {
        model = MODEL_STVENANTKIRCHHOFF_FORCES;
        expected_nlhs = 2;
    } else if (strcmp(Material_Model, "StVenantKirchhoff_jacobianSlow") == 0) {
        model = MODEL_STVENANTKIRCHHOFF_JACOBIAN_SLOW;
        expected_nlhs = 3;
    } else if (strcmp(Material_Model, "StVenantKirchhoff_jacobian") == 0) {
        model = MODEL_STVENANTKIRCHHOFF_JACOBIAN;
        expected_nlhs = 3;
    } else if (strcmp(Material_Model, "StVenantKirchhoff_stress") == 0) {
        model = MODEL_STVENANTKIRCHHOFF_STRESS;
        expected_nlhs = 2;
    } else if (strcmp(Material_Model, "NeoHookean_forces") == 0) {
        model = MODEL_NEOHOOKEAN_FORCES;
        expected_nlhs = 2;
    } else if (strcmp(Material_Model, "NeoHookean_jacobian") == 0) {
        model = MODEL_NEOHOOKEAN_JACOBIAN;
        expected_nlhs = 3;
    } else if (strcmp(Material_Model, "NeoHookean_jacobianSlow") == 0) {
        model = MODEL_NEOHOOKEAN_JACOBIAN_SLOW;
        expected_nlhs = 3;
    } else if (strcmp(Material_Model, "NeoHookean_stress") == 0) {
        model = MODEL_NEOHOOKEAN_STRESS;
        expected_nlhs = 2;
    } else if (strcmp(Material_Model, "NeoHookean_prestress") == 0) {
        model = MODEL_NEOHOOKEAN_PRESTRESS;
        expected_nrhs = 12;
        expected_nlhs = 6;
    } else if (strcmp(Material_Model, "RaghavanVorp_forces") == 0) {
        model = MODEL_RAGHAVANVORP_FORCES;
        expected_nlhs = 2;
    } else if (strcmp(Material_Model, "RaghavanVorp_jacobian") == 0) {
        model = MODEL_RAGHAVANVORP_JACOBIAN;
        expected_nlhs = 3;
    } else if (strcmp(Material_Model, "RaghavanVorp_jacobianSlow") == 0) {
        model = MODEL_RAGHAVANVORP_JACOBIAN_SLOW;
        expected_nlhs = 3;
    } else if (strcmp(Material_Model, "RaghavanVorp_stress") == 0) {
        model = MODEL_RAGHAVANVORP_STRESS;
        expected_nlhs = 2;
    } else {
        mxFree(Material_Model);
        mexErrMsgTxt("Unknown material model.");
    }
    if (nrhs != expected_nrhs) {
        mxFree(Material_Model);
        if (expected_nrhs == 12) {
            mexErrMsgTxt("12 inputs are required for NeoHookean_prestress.");
        }
        mexErrMsgTxt("11 inputs are required for this material model.");
    }
    if (nlhs != expected_nlhs) {
        mxFree(Material_Model);
        mexErrMsgTxt("Incorrect number of output arguments for material model.");
    }

    mexRequireIntAddressableInputs(nrhs, prhs);
    int dim = mexCheckedPositiveIntScalar(prhs[0], "dimension");
    int nln = mexCheckedPositiveIntScalar(prhs[5], "local node count");
    int noe = mexCheckedSizeToInt(mxGetN(prhs[4]), "element count");
    int NumQuadPoints = mexCheckedSizeToInt(mxGetN(prhs[6]), "quadrature point count");
    int nln2 = mexCheckedMulInt(nln, nln, "local matrix size");

    switch (model) {
    case MODEL_LINEAR_FORCES:
    case MODEL_SEMMT_FORCES:
    case MODEL_STVENANTKIRCHHOFF_FORCES:
    case MODEL_NEOHOOKEAN_FORCES:
    case MODEL_RAGHAVANVORP_FORCES:
        (void)mexCheckedMulInt(mexCheckedMulInt(nln, noe, "force output size"),
                               dim, "force output size");
        break;
    case MODEL_LINEAR_JACOBIAN_SLOW:
    case MODEL_LINEAR_JACOBIAN:
    case MODEL_SEMMT_JACOBIAN_SLOW:
    case MODEL_SEMMT_JACOBIAN:
    case MODEL_STVENANTKIRCHHOFF_JACOBIAN_SLOW:
    case MODEL_STVENANTKIRCHHOFF_JACOBIAN:
    case MODEL_NEOHOOKEAN_JACOBIAN:
    case MODEL_NEOHOOKEAN_JACOBIAN_SLOW:
    case MODEL_RAGHAVANVORP_JACOBIAN:
    case MODEL_RAGHAVANVORP_JACOBIAN_SLOW:
        (void)mexCheckedMulInt(
            mexCheckedMulInt(mexCheckedMulInt(nln2, noe, "Jacobian output size"),
                             dim, "Jacobian output size"),
            dim, "Jacobian output size");
        break;
    case MODEL_LINEAR_STRESS:
    case MODEL_STVENANTKIRCHHOFF_STRESS:
    case MODEL_NEOHOOKEAN_STRESS:
    case MODEL_RAGHAVANVORP_STRESS:
        (void)mexCheckedMulInt(
            noe, mexCheckedMulInt(dim, dim, "stress output size"),
            "stress output size");
        break;
    case MODEL_NEOHOOKEAN_PRESTRESS:
        (void)mexCheckedMulInt(
            mexCheckedMulInt(mexCheckedMulInt(nln2, noe, "prestress Jacobian output size"),
                             dim, "prestress Jacobian output size"),
            dim, "prestress Jacobian output size");
        (void)mexCheckedMulInt(
            mexCheckedMulInt(mexCheckedMulInt(noe, NumQuadPoints, "prestress state output size"),
                             dim, "prestress state output size"),
            dim, "prestress state output size");
        break;
    default:
        break;
    }

    switch (model) {
    case MODEL_LINEAR_FORCES:
            LinearElasticMaterial_forces(plhs, prhs);
            break;
    case MODEL_LINEAR_JACOBIAN_SLOW:
            LinearElasticMaterial_jacobian(plhs, prhs);
            break;
    case MODEL_LINEAR_JACOBIAN:
        if (dim == 2)
        {
            LinearElasticMaterial_jacobianFast2D(plhs, prhs);
        }

        if (dim == 3)
        {
            LinearElasticMaterial_jacobianFast3D(plhs, prhs);
        }
        break;
    case MODEL_LINEAR_STRESS:
            LinearElasticMaterial_stress(plhs, prhs);
            break;
    case MODEL_SEMMT_FORCES:
            SEMMTMaterial_forces(plhs, prhs);
            break;
    case MODEL_SEMMT_JACOBIAN_SLOW:
            SEMMTMaterial_jacobian(plhs, prhs);
            break;
    case MODEL_SEMMT_JACOBIAN:
        if (dim == 2)
        {
            SEMMTMaterial_jacobianFast2D(plhs, prhs);
        }

        if (dim == 3)
        {
            SEMMTMaterial_jacobianFast3D(plhs, prhs);
        }
        break;
    case MODEL_STVENANTKIRCHHOFF_FORCES:
            StVenantKirchhoffMaterial_forces(plhs, prhs);
            break;
    case MODEL_STVENANTKIRCHHOFF_JACOBIAN_SLOW:
            StVenantKirchhoffMaterial_jacobian(plhs, prhs);
            break;
    case MODEL_STVENANTKIRCHHOFF_JACOBIAN:
        if (dim == 2)
        {
            StVenantKirchhoffMaterial_jacobianFast2D(plhs, prhs);
        }

        if (dim == 3)
        {
            StVenantKirchhoffMaterial_jacobianFast3D(plhs, prhs);
        }
        break;
    case MODEL_STVENANTKIRCHHOFF_STRESS:
            StVenantKirchhoffMaterial_stress(plhs, prhs);
            break;
    case MODEL_NEOHOOKEAN_FORCES:
            NeoHookeanMaterial_forces(plhs, prhs);
            break;
    case MODEL_NEOHOOKEAN_JACOBIAN:
            NeoHookeanMaterial_jacobianFast(plhs, prhs);
            break;
    case MODEL_NEOHOOKEAN_JACOBIAN_SLOW:
            NeoHookeanMaterial_jacobian(plhs, prhs);
            break;
    case MODEL_NEOHOOKEAN_STRESS:
            NeoHookeanMaterial_stress(plhs, prhs);
            break;
    case MODEL_NEOHOOKEAN_PRESTRESS:
            NeoHookeanMaterial_prestress(plhs, prhs);
            break;
    case MODEL_RAGHAVANVORP_FORCES:
            RaghavanVorpMaterial_forces(plhs, prhs);
            break;
    case MODEL_RAGHAVANVORP_JACOBIAN:
            RaghavanVorpMaterial_jacobianFast(plhs, prhs);
            break;
    case MODEL_RAGHAVANVORP_JACOBIAN_SLOW:
            RaghavanVorpMaterial_jacobian(plhs, prhs);
            break;
    case MODEL_RAGHAVANVORP_STRESS:
            RaghavanVorpMaterial_stress(plhs, prhs);
            break;
    default:
            break;
    }

    mxFree(Material_Model);

}
/*************************************************************************/
