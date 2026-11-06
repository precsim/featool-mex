function info = build_octave(varargin)
%BUILD_OCTAVE Build Octave MEX targets from build_manifest.m.
%
%   BUILD_OCTAVE() builds all targets using mkoctfile --mex.
%   BUILD_OCTAVE('target', NAME) builds one target or a cell array of names.
%   BUILD_OCTAVE('openmp', true) enables -fopenmp for supported targets.
%
% MATLAB and Octave artifacts are intentionally written to different
% directories even when Octave uses a generic .mex extension.

rootdir = fileparts(mfilename('fullpath'));

optdef.clean      = false;
optdef.srcdir     = fullfile(rootdir, 'src');
optdef.outdir     = '';
optdef.target     = 'all';
optdef.openmp     = false;
optdef.silent     = false;
optdef.extra_args = {};
optdef.metadata   = true;

if mod(length(varargin), 2) ~= 0
    error('BUILD_OCTAVE:Options', ...
        'Options must be supplied as property/value pairs.');
end

for i = 1:2:length(varargin)
    key = varargin{i};
    if ~ischar(key)
        error('BUILD_OCTAVE:Options', 'Option names must be character arrays.');
    end
    if ~isfield(optdef, key)
        error('BUILD_OCTAVE:Options', 'Unknown option: %s', key);
    end
    optdef = setfield(optdef, key, varargin{i + 1}); %#ok<SFLD>
end
opt = optdef;

mx = mexext();
if isempty(opt.outdir)
    opt.outdir = fullfile(rootdir, 'dist', 'octave', octave_platform_tag());
end

targets = select_targets(build_manifest(), opt.target);

if opt.clean
    clean_output(opt.outdir, mx);
    info = [];
    return
end

if ~exist(opt.outdir, 'dir')
    mkdir(opt.outdir);
end

for i = 1:length(targets)
    target = targets(i);
    source_file = fullfile(opt.srcdir, target.source);
    if ~exist(source_file, 'file')
        error('BUILD_OCTAVE:SourceMissing', ...
            'Source file does not exist: %s', source_file);
    end

    deps = cell(1, length(target.deps));
    for j = 1:length(target.deps)
        deps{j} = fullfile(opt.srcdir, target.deps{j});
        if ~exist(deps{j}, 'file')
            error('BUILD_OCTAVE:DependencyMissing', ...
                'Dependency for %s does not exist: %s', target.name, deps{j});
        end
    end

    output_file = fullfile(opt.outdir, [target.name '.' mx]);
    args = {'--mex'};
    if ~opt.silent
        args{end + 1} = '-v';
        fprintf(1, 'Building Octave target %s\n', target.name);
    end

    for j = 1:length(target.defines)
        args{end + 1} = ['-D' target.defines{j}];
    end
    if opt.openmp && target.openmp
        args{end + 1} = '-fopenmp';
    end
    if ~isempty(opt.extra_args)
        if ~iscell(opt.extra_args)
            error('BUILD_OCTAVE:Options', 'extra_args must be a cell array.');
        end
        args = [args opt.extra_args]; %#ok<AGROW>
    end

    args = [args {'-o', output_file, source_file} deps]; %#ok<AGROW>
    if target.blas
        args{end + 1} = '-lblas';
    end

    [build_output, status] = mkoctfile(args{:});
    if ~opt.silent && ~isempty(build_output)
        fprintf(1, '%s', build_output);
    end
    if status ~= 0
        error('BUILD_OCTAVE:Compile', ...
            'mkoctfile failed for target %s with status %d.', target.name, status);
    end
end

copy_wrappers(opt.srcdir, opt.outdir);

target_names = cell(1, length(targets));
for i = 1:length(targets)
    target_names{i} = targets(i).name;
end

info = make_build_info('octave', version(), mx, opt.openmp, ...
    'mex-compat', target_names, octave_compiler_description());
if opt.metadata
    write_build_info(opt.outdir, info);
end

end


function targets = select_targets(all_targets, requested)
if ischar(requested)
    if strcmpi(requested, 'all')
        targets = all_targets;
        return
    end
    requested = {requested};
elseif ~iscell(requested)
    error('BUILD_OCTAVE:Target', ...
        'target must be ''all'', a target name, or a cell array.');
end

targets = all_targets([]);
for i = 1:length(requested)
    found = 0;
    for j = 1:length(all_targets)
        if strcmpi(requested{i}, all_targets(j).name)
            targets(end + 1) = all_targets(j); %#ok<AGROW>
            found = 1;
            break
        end
    end
    if ~found
        error('BUILD_OCTAVE:Target', 'Unknown target: %s', requested{i});
    end
end
end


function copy_wrappers(srcdir, outdir)
files = dir(fullfile(srcdir, '*.m'));
for i = 1:length(files)
    copyfile(fullfile(srcdir, files(i).name), fullfile(outdir, files(i).name));
end
end


function clean_output(outdir, mx)
if ~exist(outdir, 'dir')
    return
end
patterns = {['*.' mx], '*.m', 'BUILD-INFO.json', 'SHA256SUMS', ...
            'COMPATIBILITY.txt', '*-ABI.json', '*-ABI.txt'};
for i = 1:length(patterns)
    files = dir(fullfile(outdir, patterns{i}));
    for j = 1:length(files)
        delete(fullfile(outdir, files(j).name));
    end
end
end


function tag = octave_platform_tag()
if ispc
    tag = 'windows-x86_64';
elseif ismac
    machine = computer();
    if ~isempty(strfind(machine, 'ARM')) || ~isempty(strfind(machine, 'aarch64'))
        tag = 'macos-arm64';
    else
        tag = 'macos-x86_64';
    end
else
    tag = 'linux-x86_64';
end
end


function description = octave_compiler_description()
description = 'unknown';
try
    [status, cc] = system('mkoctfile -p CC');
    if status == 0
        description = strtrim(cc);
    end
    [status, cxx] = system('mkoctfile -p CXX');
    if status == 0 && ~isempty(strtrim(cxx))
        description = [description '; CXX=' strtrim(cxx)];
    end
catch
end
end
