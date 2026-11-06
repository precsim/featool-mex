function smoke_mex(artifact_dir)
%SMOKE_MEX Functional smoke tests shared by MATLAB and Octave.
%
% Keep this file compatible with MATLAB R2011a.  It intentionally uses
% only basic language features so the exact same tests can run on legacy
% compatibility builders and newer forward-runtime validation jobs.

if nargin ~= 1 || isempty(artifact_dir)
    error('SMOKE_MEX:Usage', 'An artifact directory is required.');
end
if ~exist(artifact_dir, 'dir')
    error('SMOKE_MEX:ArtifactDir', ...
        'Artifact directory does not exist: %s', artifact_dir);
end

original_dir = pwd;
cd(artifact_dir);
artifact_dir = pwd;
cd(original_dir);

clear mex
addpath(artifact_dir, '-begin');
cleanup = onCleanup(@() rmpath(artifact_dir)); %#ok<NASGU>

fprintf(1, 'Running MEX smoke tests from %s\n', artifact_dir);

targets = {'assemble_f', 'assemble_m', 'assemble_s', 'assemble_se', ...
           'chkmex', 'earrind', 'eindarr', 'findsp', 'fsetop', 'fsparse', ...
           'iluk_Cmex', 'iluk_Cmex_nosymb', 'spsetd'};
for i = 1:length(targets)
    check_resolved(targets{i}, fullfile(artifact_dir, ...
        [targets{i} '.' mexext()]));
end
check_resolved('iluk', fullfile(artifact_dir, 'iluk.m'));

check_scalar(chkmex(), 1, 'chkmex');

out = eindarr([10 20 30], [3 1]);
check_equal(out, [30 10], 0, 'eindarr');

out = earrind([10; 20; 30], 3);
check_equal(out, 30, 0, 'earrind');

A = sparse([1 3], [1 2], [4 5], 3, 2);
[jc, ir, ind, vals] = findsp(A);
check_equal(double(jc), [0 1 2], 0, 'findsp column pointers');
check_equal(double(ir), [0 2], 0, 'findsp row indices');
check_equal(double(ind), [0 5], 0, 'findsp linear indices');
check_equal(vals, [4 5], 0, 'findsp values');

unique_values = fsetop('unique', [3 1 3 2]);
check_equal(sort(unique_values), [1 2 3], 0, 'fsetop unique');

S = fsparse([1; 2], [1; 2], [1 + 2i; 3 + 4i], [2 2]);
S_expected = sparse([1 2], [1 2], [1 + 2i 3 + 4i], 2, 2);
check_equal(full(S), full(S_expected), 1e-12, 'fsparse complex');

S = sparse([2 -1; -1 2]);
S_set = spsetd(S, 1);
check_equal(full(S_set), [1 0; -1 2], 0, 'spsetd');

S_complex = sparse([1 + 2i 3 + 4i; 5 + 6i 7 + 8i]);
S_complex_set = spsetd(S_complex, 1);
check_equal(full(S_complex_set), [1 0; 5 + 6i 7 + 8i], 0, ...
    'spsetd complex');

[L, U, levels] = iluk_Cmex(speye(3), 0);
check_equal(full(L), eye(3), 1e-12, 'iluk_Cmex L');
check_equal(full(U), eye(3), 1e-12, 'iluk_Cmex U');
[L2, U2] = iluk_Cmex_nosymb(speye(3), levels);
check_equal(full(L2), eye(3), 1e-12, 'iluk_Cmex_nosymb L');
check_equal(full(U2), eye(3), 1e-12, 'iluk_Cmex_nosymb U');
[L3, U3] = iluk(speye(3), 0);
check_equal(full(L3), eye(3), 1e-12, 'iluk wrapper L');
check_equal(full(U3), eye(3), 1e-12, 'iluk wrapper U');

[rows, cols, coef] = assemble_m(1, 1, 1, 1, 1, 1);
check_equal(rows, 1, 0, 'assemble_m rows');
check_equal(cols, 1, 0, 'assemble_m columns');
check_equal(coef, 1, 1e-12, 'assemble_m values');

[rows, coef] = assemble_se(2, 1, 1, 1, 1, 1);
check_equal(rows, 1, 0, 'assemble_se rows');
check_equal(coef, 2, 1e-12, 'assemble_se values');

[rows, coef] = assemble_s(2, 'Linear_forces', [1 .25], [0; 0], ...
    1, 1, 1, [1 0 0 1], 1, 1, [0 0]);
check_equal(rows, [1; 2], 0, 'assemble_s rows');
check_equal(coef, [0; 0], 1e-12, 'assemble_s values');

[arows, acols, acoef, rrows, rcoef, stress] = assemble_s(3, ...
    'NeoHookean_prestress', [1 .25], [0; 0; 0], 1, 1, 1, ...
    [1 0 0 0 1 0 0 0 1], 1, 1, [0 0 0], zeros(9, 1));
check_scalar(numel(arows), 9, 'assemble_s prestress rows');
check_scalar(numel(acols), 9, 'assemble_s prestress columns');
check_scalar(numel(acoef), 9, 'assemble_s prestress coefficients');
check_scalar(numel(rrows), 3, 'assemble_s prestress residual rows');
check_scalar(numel(rcoef), 3, 'assemble_s prestress residual values');
check_scalar(numel(stress), 9, 'assemble_s prestress stress');

[rows, cols, coef] = assemble_f('Stokes', 1, 1, 1, 1, 1, 1, ...
    1, 1, 1, 1, 1, 1);
check_equal(rows, [1; 1; 2], 0, 'assemble_f rows');
check_equal(cols, [1; 2; 1], 0, 'assemble_f columns');
check_equal(coef, [2; -1; 1], 1e-12, 'assemble_f values');

fprintf(1, 'All MEX smoke tests passed.\n');
end


function check_resolved(name, expected)
resolved = which(name);
if ispc
    matches = strcmpi(resolved, expected);
else
    matches = strcmp(resolved, expected);
end
if ~matches
    error('SMOKE_MEX:Resolution', ...
        '%s resolved to %s instead of artifact file %s.', ...
        name, resolved, expected);
end
end


function check_scalar(actual, expected, name)
if ~isscalar(actual) || actual ~= expected
    error('SMOKE_MEX:Failure', '%s returned an unexpected value.', name);
end
end


function check_equal(actual, expected, tolerance, name)
if ~isequal(size(actual), size(expected))
    error('SMOKE_MEX:Failure', '%s returned an unexpected size.', name);
end

if tolerance == 0
    ok = isequal(actual, expected);
else
    delta = abs(actual(:) - expected(:));
    ok = all(delta <= tolerance);
end

if ~ok
    error('SMOKE_MEX:Failure', '%s returned unexpected data.', name);
end
end
