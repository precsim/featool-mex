function info = make_build_info(runtime_name, runtime_version, mex_extension, ...
    openmp, api, target_names, compiler_description, linker_description)
%MAKE_BUILD_INFO Build metadata shared by MATLAB and Octave build drivers.

if nargin < 8
    linker_description = 'unknown';
end

info.runtime = runtime_name;
info.arch = platform_tag_from_mex(mex_extension);
info.built_with = runtime_version;
info.mex_extension = mex_extension;
info.openmp = logical(openmp);
info.api = api;
info.source_sha = getenv('MEX_SOURCE_SHA');
if isempty(info.source_sha)
    info.source_sha = getenv('GITHUB_SHA');
end
if isempty(info.source_sha)
    info.source_sha = 'unknown';
end
compiler_override = getenv('MEX_COMPILER_DESCRIPTION');
if isempty(compiler_override)
    info.compiler = compiler_description;
else
    info.compiler = compiler_override;
end
linker_override = getenv('MEX_LINKER_DESCRIPTION');
if isempty(linker_override)
    info.linker = linker_description;
else
    info.linker = linker_override;
end
info.targets = target_names;
end


function tag = platform_tag_from_mex(mx)
if strcmpi(mx, 'mexw64')
    tag = 'windows-x86_64';
elseif strcmpi(mx, 'mexa64')
    tag = 'linux-x86_64';
elseif strcmpi(mx, 'mexmaci64')
    tag = 'macos-x86_64';
elseif strcmpi(mx, 'mexmaca64')
    tag = 'macos-arm64';
elseif ispc
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
