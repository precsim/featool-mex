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

    if(nrhs!=11) {
        mexErrMsgTxt("11 inputs are required.");
    }
    if (!mxIsChar(prhs[1])) {
        mexErrMsgTxt("Second input must be a material model name.");
    }

    char *Material_Model = mxArrayToString(prhs[1]);
    if (Material_Model == NULL) {
        mexErrMsgTxt("Could not read material model name.");
    }

    int expected_nlhs = 0;
    if (strstr(Material_Model, "_forces") != NULL ||
        strstr(Material_Model, "_stress") != NULL) {
        expected_nlhs = 2;
    } else if (strstr(Material_Model, "_jacobian") != NULL) {
        expected_nlhs = 3;
    } else if (strcmp(Material_Model, "NeoHookean_prestress") == 0) {
        expected_nlhs = 6;
    }
    if (expected_nlhs == 0) {
        mxFree(Material_Model);
        mexErrMsgTxt("Unknown material model.");
    }
    if (nlhs != expected_nlhs) {
        mxFree(Material_Model);
        mexErrMsgTxt("Incorrect number of output arguments for material model.");
    }

    double* dim_ptr = mxGetPr(prhs[0]);
    int dim     = (int)(dim_ptr[0]);

    if (strcmp(Material_Model, "Linear_forces")==0)
    {
            LinearElasticMaterial_forces(plhs, prhs);
    }

    if (strcmp(Material_Model, "Linear_jacobianSlow")==0)
    {
            LinearElasticMaterial_jacobian(plhs, prhs);
    }

    if (strcmp(Material_Model, "Linear_jacobian")==0)
    {
        if (dim == 2)
        {
            LinearElasticMaterial_jacobianFast2D(plhs, prhs);
        }

        if (dim == 3)
        {
            LinearElasticMaterial_jacobianFast3D(plhs, prhs);
        }
    }

    if (strcmp(Material_Model, "Linear_stress")==0)
    {
            LinearElasticMaterial_stress(plhs, prhs);
    }

    if (strcmp(Material_Model, "SEMMT_forces")==0)
    {
            SEMMTMaterial_forces(plhs, prhs);
    }

    if (strcmp(Material_Model, "SEMMT_jacobianSlow")==0)
    {
            SEMMTMaterial_jacobian(plhs, prhs);
    }

    if (strcmp(Material_Model, "SEMMT_jacobian")==0)
    {
        if (dim == 2)
        {
            SEMMTMaterial_jacobianFast2D(plhs, prhs);
        }

        if (dim == 3)
        {
            SEMMTMaterial_jacobianFast3D(plhs, prhs);
        }
    }


    if (strcmp(Material_Model, "StVenantKirchhoff_forces")==0)
    {
            StVenantKirchhoffMaterial_forces(plhs, prhs);
    }

    if (strcmp(Material_Model, "StVenantKirchhoff_jacobianSlow")==0)
    {
            StVenantKirchhoffMaterial_jacobian(plhs, prhs);
    }

    if (strcmp(Material_Model, "StVenantKirchhoff_jacobian")==0)
    {
        if (dim == 2)
        {
            StVenantKirchhoffMaterial_jacobianFast2D(plhs, prhs);
        }

        if (dim == 3)
        {
            StVenantKirchhoffMaterial_jacobianFast3D(plhs, prhs);
        }

    }

    if (strcmp(Material_Model, "StVenantKirchhoff_stress")==0)
    {
            StVenantKirchhoffMaterial_stress(plhs, prhs);
    }

    if (strcmp(Material_Model, "NeoHookean_forces")==0)
    {
            NeoHookeanMaterial_forces(plhs, prhs);
    }

    if (strcmp(Material_Model, "NeoHookean_jacobian")==0)
    {
            NeoHookeanMaterial_jacobianFast(plhs, prhs);
    }

    if (strcmp(Material_Model, "NeoHookean_jacobianSlow")==0)
    {
            NeoHookeanMaterial_jacobian(plhs, prhs);
    }

    if (strcmp(Material_Model, "NeoHookean_stress")==0)
    {
            NeoHookeanMaterial_stress(plhs, prhs);
    }

    if (strcmp(Material_Model, "NeoHookean_prestress")==0)
    {
            NeoHookeanMaterial_prestress(plhs, prhs);
    }

    if (strcmp(Material_Model, "RaghavanVorp_forces")==0)
    {
            RaghavanVorpMaterial_forces(plhs, prhs);
    }

    if (strcmp(Material_Model, "RaghavanVorp_jacobian")==0)
    {
            RaghavanVorpMaterial_jacobianFast(plhs, prhs);
    }

    if (strcmp(Material_Model, "RaghavanVorp_jacobianSlow")==0)
    {
            RaghavanVorpMaterial_jacobian(plhs, prhs);
    }

    if (strcmp(Material_Model, "RaghavanVorp_stress")==0)
    {
            RaghavanVorpMaterial_stress(plhs, prhs);
    }

    mxFree(Material_Model);

}
/*************************************************************************/
