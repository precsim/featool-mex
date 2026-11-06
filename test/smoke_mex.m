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

out = eindarr([1 2 3; 4 5 6], [3 1]);
check_equal(out, [3 6; 1 4], 0, 'eindarr wide matrix');

out = eindarr([1 2; 3 4], [2 1]);
check_equal(out, [3 4; 1 2], 0, 'eindarr square matrix');

out = eindarr(single([10 20 30]), uint32([3 1]));
check_equal(out, single([30 10]), 0, 'eindarr single integer indices');

out = eindarr([10 20 30], int64([3 1]));
check_equal(out, [30 10], 0, 'eindarr int64 indices');

out = eindarr([10 20 30], uint64([3 1]));
check_equal(out, [30 10], 0, 'eindarr uint64 indices');

out = eindarr([10; 20; 30], [3 1]);
check_equal(out, [30 10], 0, 'eindarr vector index shape');

c_nd = reshape([4 1 3 2], [2 1 2]);
out = eindarr([10 20 30 40], c_nd);
check_equal(out, reshape([40 10 30 20], [2 1 2]), 0, 'eindarr N-D index shape');

out = eindarr([10 20 30], zeros(1, 0));
check_equal(out, zeros(1, 0), 0, 'eindarr empty indices');

bad_indices = {0, -1, 1.5, 4, NaN, Inf, int32(-1), uint32(4)};
for i = 1:length(bad_indices)
    caught = false;
    try
        out = eindarr([10 20 30], bad_indices{i}); %#ok<NASGU>
    catch
        caught = true;
    end
    if ~caught
        error('SMOKE_MEX:Failure', 'eindarr accepted an invalid index.');
    end
end

caught = false;
try
    out = eindarr(complex([1 2 3]), 1); %#ok<NASGU>
catch
    caught = true;
end
if ~caught
    error('SMOKE_MEX:Failure', 'eindarr accepted complex input.');
end

out = earrind([10; 20; 30], 3);
check_equal(out, 30, 0, 'earrind');

out = earrind([1 2; 3 4], [2 1 2]);
check_equal(out, [3 4; 1 2; 3 4], 0, 'earrind indexed rows');

out = earrind([1 2; 3 4], [1 2]);
check_equal(out, [1 2; 3 4], 0, 'earrind row range');

out = earrind([1 2; 3 4], [2 1 2], [10 20]);
check_equal(out, [110; 50; 110], 0, 'earrind weighted indexed rows');

out = earrind([1 2; 3 4], [1 2], [10 20]);
check_equal(out, [50; 110], 0, 'earrind weighted row range');

out = earrind([1 2; 3 4], zeros(1, 0));
check_equal(out, zeros(0, 2), 0, 'earrind empty indices');

out = earrind([1 2; 3 4], zeros(1, 0), [10 20]);
check_equal(out, zeros(0, 1), 0, 'earrind weighted empty indices');

out = earrind([1 2; 3 4], [1 2], 2);
check_equal(out, [6; 14], 0, 'earrind scalar weight broadcast');

bad_ranges = {[0 1], [1 3], [1 1.5], [1 NaN]};
for i = 1:length(bad_ranges)
    caught = false;
    try
        out = earrind([1 2; 3 4], bad_ranges{i}); %#ok<NASGU>
    catch
        caught = true;
    end
    if ~caught
        error('SMOKE_MEX:Failure', 'earrind accepted an invalid row range.');
    end
end

bad_index_vectors = {[1 0 2], [1 3 2], [1 1.5 2], [1 Inf 2]};
for i = 1:length(bad_index_vectors)
    caught = false;
    try
        out = earrind([1 2; 3 4], bad_index_vectors{i}); %#ok<NASGU>
    catch
        caught = true;
    end
    if ~caught
        error('SMOKE_MEX:Failure', 'earrind accepted an invalid row index.');
    end
end

caught = false;
try
    out = earrind(zeros(0, 1), [1 1]); %#ok<NASGU>
catch
    caught = true;
end
if ~caught
    error('SMOKE_MEX:Failure', 'earrind accepted a range into an empty array.');
end

bad_weights = {[], [1 2 3]};
for i = 1:length(bad_weights)
    caught = false;
    try
        out = earrind([1 2; 3 4], [1 2], bad_weights{i}); %#ok<NASGU>
    catch
        caught = true;
    end
    if ~caught
        error('SMOKE_MEX:Failure', 'earrind accepted a mismatched weight vector.');
    end
end

caught = false;
try
    out = earrind([1 2 3; 4 5 6], [1 2], [1 2]); %#ok<NASGU>
catch
    caught = true;
end
if ~caught
    error('SMOKE_MEX:Failure', 'earrind accepted a partially short weight vector.');
end

caught = false;
try
    out = earrind(complex([10; 20; 30]), 3); %#ok<NASGU>
catch
    caught = true;
end
if ~caught
    error('SMOKE_MEX:Failure', 'earrind accepted complex input.');
end

A = sparse([1 3], [1 2], [4 5], 3, 2);
[jc, ir, ind, vals] = findsp(A);
if ~isa(jc, 'uint64') || ~isa(ir, 'uint64') || ~isa(ind, 'uint64')
    error('SMOKE_MEX:Failure', 'findsp index outputs are not uint64.');
end
check_equal(double(jc), [0 1 2], 0, 'findsp column pointers');
check_equal(double(ir), [0 2], 0, 'findsp row indices');
check_equal(double(ind), [0 5], 0, 'findsp linear indices');
check_equal(vals, [4 5], 0, 'findsp values');

A_empty = sparse(3, 2);
[jc_empty, ir_empty, ind_empty, vals_empty] = findsp(A_empty);
check_equal(double(jc_empty), [0 0 0], 0, 'findsp empty column pointers');
check_equal(double(ir_empty), zeros(1, 0), 0, 'findsp empty row indices');
check_equal(double(ind_empty), zeros(1, 0), 0, 'findsp empty linear indices');
check_equal(vals_empty, zeros(1, 0), 0, 'findsp empty values');

caught = false;
try
    [jc, ir, ind, vals] = findsp(complex(A)); %#ok<ASGLU>
catch
    caught = true;
end
if ~caught
    error('SMOKE_MEX:Failure', 'findsp accepted complex sparse input.');
end

caught = false;
try
    [o1, o2, o3, o4, o5] = findsp(A); %#ok<ASGLU>
catch
    caught = true;
end
if ~caught
    error('SMOKE_MEX:Failure', 'findsp accepted more than four outputs.');
end

unique_values = fsetop('unique', [3 1 3 2]);
check_equal(sort(unique_values), [1 2 3], 0, 'fsetop unique');

unique_values = fsetop('unique', [0 -0]);
if numel(unique_values) ~= 1 || unique_values(1) ~= 0
    error('SMOKE_MEX:Failure', 'fsetop distinguishes signed zero.');
end

cell_values = fsetop('unique', {0, -0});
if numel(cell_values) ~= 1 || cell_values{1} ~= 0
    error('SMOKE_MEX:Failure', 'fsetop cell equality distinguishes signed zero.');
end

single_values = fsetop('unique', single([0 -0]));
if ~isa(single_values, 'single') || numel(single_values) ~= 1 || single_values(1) ~= 0
    error('SMOKE_MEX:Failure', 'fsetop single signed-zero handling failed.');
end

char_values = fsetop('unique', 'abca');
if ~ischar(char_values)
    error('SMOKE_MEX:Failure', 'fsetop did not preserve char class.');
end
check_equal(char_values, 'abc', 0, 'fsetop char unique');

logical_values = fsetop('unique', logical([1 0 1]));
if ~islogical(logical_values)
    error('SMOKE_MEX:Failure', 'fsetop did not preserve logical class.');
end
check_equal(logical_values, logical([1 0]), 0, 'fsetop logical unique');

empty_cells = cell(1, 2);
empty_cells{2} = [];
cell_values = fsetop('unique', empty_cells);
if numel(cell_values) ~= 1 || ~isempty(cell_values{1}) || ...
        ~isa(cell_values{1}, 'double')
    error('SMOKE_MEX:Failure', 'fsetop did not normalize unpopulated cells to [].');
end
cell_hashes = fsetop('check', empty_cells);
check_equal(cell_hashes, repmat(cell_hashes(1), 1, 2), 0, ...
    'fsetop unpopulated-cell check');

[empty_unique, empty_ia, empty_ib] = fsetop('unique', zeros(0, 3));
check_equal(empty_unique, zeros(0, 1), 0, 'fsetop zero-row unique');
check_equal(empty_ia, 1, 0, 'fsetop zero-row unique IA');
check_equal(empty_ib, [1 1 1], 0, 'fsetop zero-row unique IB');
empty_hashes = fsetop('check', zeros(0, 3));
check_equal(empty_hashes, repmat(empty_hashes(1), 1, 3), 0, ...
    'fsetop zero-row check');

[empty_member, empty_loc] = fsetop('ismember', zeros(0, 2), zeros(0, 3));
check_equal(empty_member, logical([1 1]), 0, 'fsetop zero-row ismember');
check_equal(empty_loc, [1 1], 0, 'fsetop zero-row ismember locations');

membership = fsetop('ismember', [-0 1], [0 2]);
check_equal(membership, [1 0], 0, 'fsetop signed zero ismember');

value = fsetop('intersect', -0, 0);
if numel(value) ~= 1 || value ~= 0
    error('SMOKE_MEX:Failure', 'fsetop intersect distinguishes signed zero.');
end

value = fsetop('setdiff', [-0 1], 0);
check_equal(value, 1, 0, 'fsetop signed zero setdiff');

value = fsetop('setxor', -0, 0);
if ~isempty(value)
    error('SMOKE_MEX:Failure', 'fsetop setxor distinguishes signed zero.');
end

value = fsetop('union', -0, 0);
if numel(value) ~= 1 || value ~= 0
    error('SMOKE_MEX:Failure', 'fsetop union distinguishes signed zero.');
end

S = fsparse([1; 2], [1; 2], [1 + 2i; 3 + 4i], [2 2]);
S_expected = sparse([1 2], [1 2], [1 + 2i 3 + 4i], 2, 2);
check_equal(full(S), full(S_expected), 1e-12, 'fsparse complex');

ii = repmat((1:8)', 8, 1);
jj = kron((1:8)', ones(8, 1));
vv = (1:64)';
S = fsparse(ii, jj, vv, [8 8], 'sort', 8);
S_expected = sparse(ii, jj, vv, 8, 8);
check_equal(full(S), full(S_expected), 0, 'fsparse limited OpenMP team');

full_complex = complex([1 0], [0 1]);
S = fsparse(full_complex);
check_equal(full(S), full_complex, 0, 'fsparse complex full conversion');

caught = false;
try
    S = fsparse(double(intmax('int32')) + 1, 1, 1); %#ok<NASGU>
catch
    caught = true;
end
if ~caught
    error('SMOKE_MEX:Failure', 'fsparse accepted an index above INT_MAX.');
end

caught = false;
try
    S = fsparse(double(intmax('int32')), 1, 1); %#ok<NASGU>
catch
    caught = true;
end
if ~caught
    error('SMOKE_MEX:Failure', 'fsparse accepted the unsafe INT_MAX index boundary.');
end

caught = false;
try
    S = fsparse(1, 1, 1, [1 1], 'sort', double(intmax('int32'))); %#ok<NASGU>
catch
    caught = true;
end
if ~caught
    error('SMOKE_MEX:Failure', 'fsparse accepted the unsafe INT_MAX thread count.');
end

S = sparse([2 -1; -1 2]);
S_set = spsetd(S, 1);
check_equal(full(S_set), [1 0; -1 2], 0, 'spsetd');

S_duplicate_set = spsetd(S, [1 1]);
check_equal(full(S_duplicate_set), [1 0; -1 2], 0, 'spsetd duplicate rows');

S_multi = sparse(reshape(1:9, 3, 3));
S_multi_set = spsetd(S_multi, [3 2 3]);
check_equal(full(S_multi_set), [1 4 7; 0 1 0; 0 0 1], 0, 'spsetd multiple rows');

check_equal(full(S), [2 -1; -1 2], 0, 'spsetd input unchanged');

S_complex = sparse([1 + 2i 3 + 4i; 5 + 6i 7 + 8i]);
caught = false;
try
    S_complex_set = spsetd(S_complex, 1); %#ok<NASGU>
catch
    caught = true;
end
if ~caught
    error('SMOKE_MEX:Failure', 'spsetd accepted complex sparse input.');
end

caught = false;
try
    spsetd(S, 1);
catch
    caught = true;
end
if ~caught
    error('SMOKE_MEX:Failure', 'spsetd allowed unsafe no-output mutation.');
end

S_far = sparse(100, 100);
S_far(100, 100) = 2;
S_far_set = spsetd(S_far, 100);
check_equal(full(S_far_set(100, 100)), 1, 0, 'spsetd far row');

S_empty_selection = spsetd(sparse(1000000, 1), []);
check_equal(size(S_empty_selection), [1000000 1], 0, 'spsetd empty selection size');
check_scalar(nnz(S_empty_selection), 0, 'spsetd empty selection values');

caught = false;
try
    S_empty_set = spsetd(sparse(2, 2), 1); %#ok<NASGU>
catch
    caught = true;
end
if ~caught
    error('SMOKE_MEX:Failure', ...
        'spsetd accepted a requested row without a diagonal entry.');
end

caught = false;
try
    S_empty_set = spsetd(sparse(2, 2), 3); %#ok<NASGU>
catch
    caught = true;
end
if ~caught
    error('SMOKE_MEX:Failure', ...
        'spsetd accepted an out-of-bounds row for an empty sparse matrix.');
end

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

[rows, coef] = assemble_s(2, 'Linear_forces', [1 .25], [0; 0], ...
    [], 1, 1, [1 0 0 1], 1, 1, [0 0]);
check_equal(rows, zeros(0, 1), 0, 'assemble_s empty connectivity rows');
check_equal(coef, zeros(0, 1), 0, 'assemble_s empty connectivity values');

bad_connectivity = {0, 1.5, 2, double(intmax('int32')) + 1};
for i = 1:length(bad_connectivity)
    caught = false;
    try
        [rows, coef] = assemble_s(2, 'Linear_forces', [1 .25], [0; 0], ...
            bad_connectivity{i}, 1, 1, [1 0 0 1], 1, 1, [0 0]); %#ok<ASGLU>
    catch
        caught = true;
    end
    if ~caught
        error('SMOKE_MEX:Failure', ...
            'assemble_s accepted invalid element connectivity.');
    end
end

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

[rows, cols, coef] = assemble_f('convective_Oseen', 1, 1, 1, 1, 1, ...
    1, 1, 1, 1, 1, 1);
check_equal(rows, 1, 0, 'assemble_f convective rows');
check_equal(cols, 1, 0, 'assemble_f convective columns');
check_equal(coef, 1, 1e-12, 'assemble_f convective values');

[rows, cols, coef] = assemble_f('convective_Oseen', 1, 1, [], 1, 1, ...
    1, 1, 1, 1, 1, 1);
check_equal(rows, zeros(0, 1), 0, 'assemble_f empty connectivity rows');
check_equal(cols, zeros(0, 1), 0, 'assemble_f empty connectivity columns');
check_equal(coef, zeros(0, 1), 0, 'assemble_f empty connectivity values');

bad_connectivity = {0, 1.5, 2, double(intmax('int32')) + 1};
for i = 1:length(bad_connectivity)
    caught = false;
    try
        [rows, cols, coef] = assemble_f('convective_Oseen', 1, 1, ...
            bad_connectivity{i}, 1, 1, 1, 1, 1, 1, 1, 1); %#ok<ASGLU>
    catch
        caught = true;
    end
    if ~caught
        error('SMOKE_MEX:Failure', ...
            'assemble_f accepted invalid element connectivity.');
    end
end

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
