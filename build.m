function info = build(varargin)
%BUILD Build MATLAB MEX targets from the deterministic manifest.
%
%   BUILD() builds all targets as serial, legacy Matrix API MEX files.
%
%   BUILD('target', NAME) builds one target. NAME may also be a cell array
%   of target names.
%
%   BUILD(..., 'openmp', true) enables OpenMP for targets that declare
%   OpenMP support. Baseline/release builds should leave this false.
%
%   BUILD(..., 'api', 'legacy') selects the separate-complex Matrix API.
%   On MATLAB versions that understand -R2017b, BUILD passes -R2017b.
%   Older MATLAB versions use -largeArrayDims.
%
%   BUILD(..., 'mexopts', FILE) uses an explicit MEX options file. A struct
%   with fields c and cpp may be supplied for separate language-specific
%   files. Local opt/ files are never auto-discovered so release ABI
%   settings cannot be changed accidentally.
%
%   BUILD(..., 'compiler', NAME) selects an installed compiler by matching
%   NAME against MATLAB's compiler configuration names. This is primarily
%   used by hosted Windows CI to select the MinGW support package because
%   the sources require C99 variable-length arrays.
%
% Keep this file compatible with MATLAB R2011a.

% Copyright 2013-2026 Precise Simulation, Ltd.

rootdir = fileparts(mfilename('fullpath'));

optdef.clean    = false;
optdef.srcdir   = fullfile(rootdir, 'src');
optdef.outdir   = '';
optdef.target   = 'all';
optdef.openmp   = false;
optdef.silent   = false;
optdef.api      = 'legacy';
optdef.r2018a   = false;
optdef.ver      = version();
optdef.mx       = mexext();
optdef.mexopts  = '';
optdef.compiler = '';
optdef.metadata = true;

if mod(length(varargin), 2) ~= 0
    error('BUILD:Options', 'Options must be supplied as property/value pairs.');
end

for i = 1:2:length(varargin)
    key = varargin{i};
    if ~ischar(key)
        error('BUILD:Options', 'Option names must be character arrays.');
    end
    if ~isfield(optdef, key)
        error('BUILD:Options', 'Unknown option: %s', key);
    end
    optdef = setfield(optdef, key, varargin{i + 1}); %#ok<SFLD>
end
opt = optdef;

if opt.r2018a
    error('BUILD:InterleavedComplex', ...
        'The sources require the legacy separate-complex API; -R2018a is unsupported.');
end
if ~strcmpi(opt.api, 'legacy')
    error('BUILD:API', ...
        'Only api=''legacy'' is supported because fsparse uses mxGetPi.');
end

if isempty(opt.outdir)
    opt.outdir = fullfile(rootdir, 'dist', 'matlab', platform_tag(opt.mx));
end

targets = build_manifest();
targets = select_targets(targets, opt.target);

if opt.clean
    clean_output(opt.outdir, opt.mx, opt.srcdir);
    info = [];
    return
end

if ~exist(opt.outdir, 'dir')
    mkdir(opt.outdir);
end

apiarg = legacy_api_arg(opt.ver);

for i = 1:length(targets)
    target = targets(i);
    source_file = fullfile(opt.srcdir, target.source);
    if ~exist(source_file, 'file')
        error('BUILD:SourceMissing', 'Source file does not exist: %s', source_file);
    end

    deps = cell(1, length(target.deps));
    for j = 1:length(target.deps)
        deps{j} = fullfile(opt.srcdir, target.deps{j});
        if ~exist(deps{j}, 'file')
            error('BUILD:DependencyMissing', ...
                'Dependency for %s does not exist: %s', target.name, deps{j});
        end
    end

    args = {apiarg};
    if ~opt.silent
        args{end + 1} = '-v';
        fprintf(1, 'Building MATLAB target %s\n', target.name);
    end

    for j = 1:length(target.defines)
        args{end + 1} = ['-D' target.defines{j}];
    end

    explicit_mexopts_file = target_mexopts(opt.mexopts, target.language);
    mexopts_file = explicit_mexopts_file;
    if isempty(mexopts_file) && ~isempty(opt.compiler)
        mexopts_file = compiler_mexopts(opt.compiler, target.language);
    end
    args = [args c_standard_args(target.language, opt.mx, ...
        mexopts_file, opt.compiler)]; %#ok<AGROW>
    if opt.openmp && target.openmp
        args = [args openmp_args(target.language, opt.mx, mexopts_file, ...
            opt.compiler, ~isempty(explicit_mexopts_file))]; %#ok<AGROW>
    end

    if ~isempty(mexopts_file)
        if ~exist(mexopts_file, 'file')
            error('BUILD:MexOptionsMissing', ...
                'Explicit MEX options file does not exist: %s', mexopts_file);
        end
        args = [args {'-f', mexopts_file}]; %#ok<AGROW>
    end

    args = [args {'-outdir', opt.outdir, '-output', target.name, source_file} deps]; %#ok<AGROW>
    if target.blas
        args{end + 1} = '-lmwblas';
    end

    mex(args{:});
end

copy_wrappers(opt.srcdir, opt.outdir);

target_names = cell(1, length(targets));
for i = 1:length(targets)
    target_names{i} = targets(i).name;
end

[compiler_description, linker_description] = ...
    matlab_toolchain_description(opt.compiler);
info = make_build_info('matlab', matlab_release(), opt.mx, opt.openmp, ...
    opt.api, target_names, compiler_description, linker_description);
if opt.metadata
    write_build_info(opt.outdir, info);
end

end


function arg = legacy_api_arg(verstr)
parts = sscanf(verstr, '%d.%d');
supports_r2017b = false;
if length(parts) >= 2
    supports_r2017b = parts(1) > 9 || (parts(1) == 9 && parts(2) >= 4);
end
if supports_r2017b
    arg = '-R2017b';
else
    arg = '-largeArrayDims';
end
end


function value = compiler_mexopts(compiler_name, language)
if ~ischar(compiler_name)
    error('BUILD:Compiler', 'compiler must be a character array.');
end
if strcmpi(language, 'cpp')
    matlab_language = 'C++';
else
    matlab_language = 'C';
end

configs = mex.getCompilerConfigurations(matlab_language, 'Installed');
value = '';
matches = 0;
for i = 1:length(configs)
    name = configs(i).Name;
    short_name = configs(i).ShortName;
    if ~isempty(strfind(lower(name), lower(compiler_name))) || ...
       ~isempty(strfind(lower(short_name), lower(compiler_name)))
        value = configs(i).MexOpt;
        matches = matches + 1;
    end
end
if matches == 0
    error('BUILD:Compiler', ...
        'No installed %s compiler matches "%s".', matlab_language, compiler_name);
elseif matches > 1
    error('BUILD:Compiler', ...
        'More than one installed %s compiler matches "%s".', ...
        matlab_language, compiler_name);
end
if isempty(value)
    error('BUILD:Compiler', ...
        'Compiler "%s" does not expose a MEX options file.', compiler_name);
end
end


function value = target_mexopts(config, language)
if isempty(config)
    value = '';
elseif ischar(config)
    value = config;
elseif isstruct(config) && isfield(config, language)
    value = getfield(config, language); %#ok<GFLD>
    if ~ischar(value)
        error('BUILD:MexOptions', ...
            'mexopts.%s must be a character array.', language);
    end
else
    error('BUILD:MexOptions', ...
        'mexopts must be a file path or a struct with c/cpp fields.');
end
end


function value = matlab_release()
value = '';
try
    value = version('-release');
catch
end
if isempty(value)
    full_version = version();
    token = regexp(full_version, '\(R([0-9][0-9][0-9][0-9][abAB])\)', ...
        'tokens', 'once');
    if isempty(token)
        value = full_version;
    else
        value = ['R' lower(token{1})];
    end
elseif value(1) ~= 'R' && value(1) ~= 'r'
    value = ['R' value];
end
end


function args = c_standard_args(language, mx, mexopts, compiler_name)
args = {};
if ~strcmpi(language, 'c')
    return
end

use_gnu_flags = ~strncmpi(mx, 'mexw', 4);
hint = lower([compiler_name ' ' mexopts]);
if ~isempty(strfind(hint, 'mingw')) || ...
   ~isempty(strfind(hint, 'gcc')) || ...
   ~isempty(strfind(hint, 'gnu')) || ...
   ~isempty(strfind(hint, 'tdm'))
    use_gnu_flags = true;
end
if use_gnu_flags
    args = {'CFLAGS=$CFLAGS -std=c99'};
end
end


function args = openmp_args(language, mx, mexopts, compiler_name, explicit_mexopts)
if explicit_mexopts
    args = {};
    return
end

if strncmpi(mx, 'mexw', 4)
    hint = lower([compiler_name ' ' mexopts]);
    use_gnu_flags = ~isempty(strfind(hint, 'mingw')) || ...
                    ~isempty(strfind(hint, 'gcc')) || ...
                    ~isempty(strfind(hint, 'gnu')) || ...
                    ~isempty(strfind(hint, 'tdm'));
    if use_gnu_flags
        if strcmpi(language, 'cpp')
            args = {'CXXFLAGS=$CXXFLAGS -fopenmp', 'LDFLAGS=$LDFLAGS -fopenmp'};
        else
            args = {'CFLAGS=$CFLAGS -fopenmp', 'LDFLAGS=$LDFLAGS -fopenmp'};
        end
    else
        args = {'COMPFLAGS=$COMPFLAGS /openmp'};
    end
elseif strncmpi(mx, 'mexa', 4)
    if strcmpi(language, 'cpp')
        args = {'CXXFLAGS=$CXXFLAGS -fopenmp', 'LDFLAGS=$LDFLAGS -fopenmp'};
    else
        args = {'CFLAGS=$CFLAGS -fopenmp', 'LDFLAGS=$LDFLAGS -fopenmp'};
    end
elseif strncmpi(mx, 'mexmac', 6)
    error('BUILD:OpenMPMac', ...
        'macOS OpenMP builds require an explicit mexopts file and libomp toolchain.');
else
    error('BUILD:OpenMPPlatform', 'Unsupported MEX platform for OpenMP: %s', mx);
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
    error('BUILD:Target', 'target must be ''all'', a target name, or a cell array.');
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
        error('BUILD:Target', 'Unknown target: %s', requested{i});
    end
end
end


function copy_wrappers(srcdir, outdir)
files = dir(fullfile(srcdir, '*.m'));
for i = 1:length(files)
    copyfile(fullfile(srcdir, files(i).name), fullfile(outdir, files(i).name));
end
end


function clean_output(outdir, mx, srcdir)
if ~exist(outdir, 'dir')
    return
end
patterns = {['*.' mx], 'BUILD-INFO.json', 'SHA256SUMS', ...
            'COMPATIBILITY.txt', '*-ABI.json', '*-ABI.txt'};
for i = 1:length(patterns)
    files = dir(fullfile(outdir, patterns{i}));
    for j = 1:length(files)
        delete(fullfile(outdir, files(j).name));
    end
end

wrappers = dir(fullfile(srcdir, '*.m'));
for i = 1:length(wrappers)
    wrapper = fullfile(outdir, wrappers(i).name);
    if exist(wrapper, 'file')
        delete(wrapper);
    end
end
end


function tag = platform_tag(mx)
if strcmpi(mx, 'mexw64')
    tag = 'windows-x86_64';
elseif strcmpi(mx, 'mexa64')
    tag = 'linux-x86_64';
elseif strcmpi(mx, 'mexmaci64')
    tag = 'macos-x86_64';
elseif strcmpi(mx, 'mexmaca64')
    tag = 'macos-arm64';
else
    tag = ['unknown-' mx];
end
end


function [compiler_description, linker_description] = ...
    matlab_toolchain_description(compiler_name)
compiler_description = 'unknown';
linker_description = 'unknown';
try
    if isempty(compiler_name)
        eval('cfg = mex.getCompilerConfigurations(''C'',''Selected'');');
    else
        eval('all_cfg = mex.getCompilerConfigurations(''C'',''Installed'');');
        cfg = all_cfg([]);
        for i = 1:length(all_cfg)
            if ~isempty(strfind(lower(all_cfg(i).Name), lower(compiler_name))) || ...
               ~isempty(strfind(lower(all_cfg(i).ShortName), lower(compiler_name)))
                cfg = all_cfg(i);
                break
            end
        end
    end
    if ~isempty(cfg)
        compiler_description = cfg(1).Name;
        try
            if ~isempty(cfg(1).Version)
                compiler_description = [compiler_description ' ' cfg(1).Version];
            end
        catch
        end
        try
            linker_description = cfg(1).LinkerName;
            if ~isempty(cfg(1).LinkerVersion)
                linker_description = [linker_description ' ' cfg(1).LinkerVersion];
            end
        catch
        end
    end
catch
end
end
