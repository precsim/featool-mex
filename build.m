function build( varargin )
% clear all,clc,varargin = {};
%BUILD Build/makefile for mex files.
%
%   BUILD(...) accepts additional arguments as property/value-pairs.
%
%   Property     Value/{Default}     Description
%   --------------------------------------------------------------------
%   openmp       Boolean {false}     Turns OpenMP-compilation on/off
%   srcdir       String  {pwd}       Mex file source directory
%   outdir       String  {pwd}       Mex file output directory
%   silent       Boolean {false}     Turns information display on/off
%   r2018a       Boolean {false}     Use R2018a mex flag
%   ver          String  {version}   MATLAB version string
%   mx           String  {mexext}    Mex extension identification string

% Copyright 2013-2026 Precise Simulation, Ltd.


% Default options.
optdef.clean  = false;
optdef.srcdir = fullfile(pwd(),'src');
optdef.outdir = fullfile(pwd(),'bin');
optdef.openmp = false;
optdef.silent = false;
optdef.r2018a = false;
optdef.ver    = version();
optdef.mx     = mexext();


% Merge defaults with actual inputs.
if( nargin>0 )
  opt = struct(varargin{:});
  fn = fieldnames(opt);
  for i=1:length(fn)
    optdef = setfield(optdef,fn{i},getfield(opt,fn{i}));
  end
end
opt = optdef;
if( opt.openmp )
  if( ~opt.silent )
    fprintf(1,'Compiling with OpenMP.\n');
    if( strncmpi(optdef.mx,'mexw',4) )
      fprintf(1,'\nNOTE! *** Remember to include libgomp_64-1.dll files for redistribution. ***\n\n');
      beep
    end
  end
end
if( opt.clean )
  delete( fullfile(opt.outdir,['*.',opt.mx]) );
  return
end


for srcext={'c','cpp'}

  mexopts = fullfile(pwd(),'opt',['mexopts_',srcext{1},'_',opt.mx]);
  if( opt.openmp )
    mexopts = [ mexopts, '_omp' ];
  end
  if( ispc() )
    if( verLessThan('MATLAB','9.6') )
      mexopts = [ mexopts, '.bat' ];
    else
      mexopts = [ mexopts, '.xml' ];
    end
  else
    mexopts = [ mexopts, '.sh' ];
  end
  if( exist(mexopts,'file') )
    if( ~opt.silent )
      fprintf(1,'Using mex options file %s\n', mexopts);
    end
  else
    mexopts = '';
  end

  sd = dir(fullfile(opt.srcdir,['*.',srcext{1}]));
  for i=1:length(sd)

    source_file = fullfile(opt.srcdir,sd(i).name);
    fprintf(1,'Compiling %s\n\n', source_file);


    deps = {};
    [st,dep] = system(['grep src_dep ',source_file]);
    if( st==0 && ~isempty(dep) )
      dep = strrep(strrep(strrep(dep,'#include',''),'"',''),'.h',['.',srcext{1}]);
      dep = strrep(strrep(dep,char(10),' '),char(11),' ');
      deps = regexp(strtrim(dep),'\s*','split');
      deps = strcat([opt.srcdir,filesep],deps);
    end


    args = {};
    if( ~opt.r2018a )
      args = [ args, { '-largeArrayDims' } ];
    else
      args = [ args, {'-R2018a'} ];
    end
    if( ~opt.silent )
      args = [ args, {'-v'} ];
    end
    if( ~isempty(mexopts) )
      args = [ args, {'-f', mexopts} ];
    end
    args = [ args, {'-outdir', opt.outdir, source_file}, deps ];

    mex( args{:} );
  end
end
try
  copyfile(fullfile(opt.srcdir,'*.m'),opt.outdir)
catch,end
