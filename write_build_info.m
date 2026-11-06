function write_build_info(outdir, info)
%WRITE_BUILD_INFO Write R2011a-compatible JSON without jsonencode.

if ~exist(outdir, 'dir')
    mkdir(outdir);
end

path = fullfile(outdir, 'BUILD-INFO.json');
fid = fopen(path, 'w');
if fid < 0
    error('BUILD:Metadata', 'Unable to write build metadata: %s', path);
end

fprintf(fid, '{\n');
write_json_string(fid, 'runtime', info.runtime, true);
write_json_string(fid, 'arch', info.arch, true);
write_json_string(fid, 'built_with', info.built_with, true);
write_json_string(fid, 'mex_extension', info.mex_extension, true);
fprintf(fid, '  "openmp": %s,\n', json_bool(info.openmp));
write_json_string(fid, 'api', info.api, true);
write_json_string(fid, 'source_sha', info.source_sha, true);
write_json_string(fid, 'compiler', info.compiler, true);
write_json_string(fid, 'linker', info.linker, true);
fprintf(fid, '  "targets": [');
for i = 1:length(info.targets)
    if i > 1
        fprintf(fid, ', ');
    end
    fprintf(fid, '"%s"', json_escape(info.targets{i}));
end
fprintf(fid, ']\n');
fprintf(fid, '}\n');
fclose(fid);
end


function write_json_string(fid, key, value, comma)
if comma
    suffix = ',';
else
    suffix = '';
end
fprintf(fid, '  "%s": "%s"%s\n', key, json_escape(value), suffix);
end


function value = json_bool(value_in)
if value_in
    value = 'true';
else
    value = 'false';
end
end


function value = json_escape(value)
if isempty(value)
    value = '';
end
value = strrep(value, '\', '\\');
value = strrep(value, '"', '\"');
value = strrep(value, sprintf('\n'), '\n');
value = strrep(value, sprintf('\r'), '\r');
value = strrep(value, sprintf('\t'), '\t');
end
