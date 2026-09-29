function missing = checkMexDependencies(mexFile)
%CHECKMEXDEPENDENCIES Find which DLLs a MEX file needs but Windows can't find.
%   MISSING = CHECKMEXDEPENDENCIES(MEXFILE) reads the import table of
%   MEXFILE (e.g. which('Screen')) and of every non-system DLL it pulls in,
%   and looks each DLL up the way Windows would: the MEX file's folder,
%   System32, then the folders on the PATH environment variable. Prints the
%   dependency tree and returns the names of the DLLs that were not found.
%
%   Use this when MATLAB reports "Invalid MEX-file ... The specified module
%   could not be found".

if nargin < 1; mexFile = which('Screen'); end
assert(exist(mexFile, 'file') == 2 || exist(mexFile, 'file') == 3, ...
  'checkMexDependencies:notFound', 'File not found: %s', mexFile);

sys32 = fullfile(getenv('SystemRoot'), 'System32');
pathDirs = strsplit(getenv('PATH'), pathsep);
pathDirs = pathDirs(~cellfun(@isempty, pathDirs));

fprintf('\nPATH entries mentioning gstreamer:\n');
gst = pathDirs(contains(lower(pathDirs), 'gstreamer'));
if isempty(gst); fprintf('  (none)\n'); else; fprintf('  %s\n', gst{:}); end
fprintf('GSTREAMER_1_0_ROOT_MSVC_X86_64 = %s\n\n', getenv('GSTREAMER_1_0_ROOT_MSVC_X86_64'));

visited = containers.Map();
missing = {};
fprintf('Dependencies of %s\n', mexFile);
walk(mexFile, fileparts(mexFile), 1);

if isempty(missing)
  fprintf('\nAll DLLs were found. The problem is something else, e.g. a wrong DLL version.\n');
else
  fprintf('\nMISSING: %s\n', strjoin(unique(missing), ', '));
end

  function walk(file, appDir, depth)
    try
      imports = peImports(file);
    catch ex
      fprintf('%s(could not read imports: %s)\n', repmat('  ', 1, depth), ex.message);
      return;
    end
    for i = 1:numel(imports)
      name = imports{i};
      key = lower(name);
      if startsWith(key, {'api-ms-win-', 'ext-ms-'}) % Windows API sets
        continue;
      end
      if isKey(visited, key); continue; end
      where = locate(name, appDir);
      visited(key) = where;
      indent = repmat('  ', 1, depth);
      if isempty(where)
        fprintf('%s%-32s MISSING\n', indent, name);
        missing{end+1} = name; %#ok<AGROW>
      elseif startsWith(lower(where), lower(sys32))
        fprintf('%s%-32s system\n', indent, name);
      elseif startsWith(lower(where), lower(matlabroot))
        fprintf('%s%-32s matlab\n', indent, name);
      else
        fprintf('%s%-32s %s\n', indent, name, where);
        walk(where, appDir, depth + 1);
      end
    end
  end

  function where = locate(name, appDir)
    where = '';
    % MATLAB's bin folder supplies libmx/libmex; its JRE (loaded at startup)
    % supplies some older VC runtimes such as msvcr100.dll
    matlabDirs = {fullfile(matlabroot, 'bin', 'win64'), ...
      fullfile(matlabroot, 'sys', 'java', 'jre', 'win64', 'jre', 'bin')};
    for d = [{appDir, sys32, getenv('SystemRoot')}, matlabDirs, pathDirs]
      f = fullfile(d{1}, name);
      if exist(f, 'file'); where = f; return; end
    end
  end
end

function names = peImports(file)
% Parse the import directory of a PE32/PE32+ image.
fid = fopen(file, 'r', 'l');
assert(fid > 0, 'cannot open file');
c = onCleanup(@() fclose(fid));
fseek(fid, 60, 'bof'); peOff = fread(fid, 1, 'uint32');
fseek(fid, peOff, 'bof');
assert(isequal(fread(fid, 4, 'uint8')', [80 69 0 0]), 'not a PE file');
fseek(fid, 2, 'cof'); nSections = fread(fid, 1, 'uint16');
fseek(fid, 12, 'cof'); optSize = fread(fid, 1, 'uint16');
fseek(fid, 2, 'cof');
optOff = ftell(fid);
magic = fread(fid, 1, 'uint16');
if magic == hex2dec('20B'); ddOff = optOff + 112; else; ddOff = optOff + 96; end
fseek(fid, ddOff + 8, 'bof'); % data directory 1 = imports
importRva = fread(fid, 1, 'uint32');
% section table
fseek(fid, optOff + optSize, 'bof');
sec = zeros(nSections, 3); % [virtualAddress virtualSize rawPointer]
for s = 1:nSections
  fseek(fid, 8, 'cof');
  vsize = fread(fid, 1, 'uint32'); va = fread(fid, 1, 'uint32');
  rawSize = fread(fid, 1, 'uint32'); raw = fread(fid, 1, 'uint32');
  sec(s,:) = [va max(vsize, rawSize) raw];
  fseek(fid, 16, 'cof');
end
toOff = @(rva) rvaToOffset(rva, sec);
names = {};
if importRva == 0; return; end
p = toOff(importRva);
while true
  fseek(fid, p + 12, 'bof');
  nameRva = fread(fid, 1, 'uint32');
  if isempty(nameRva) || nameRva == 0; break; end
  fseek(fid, toOff(nameRva), 'bof');
  bytes = fread(fid, 260, 'uint8=>char')';
  names{end+1} = bytes(1:find(bytes == char(0), 1) - 1); %#ok<AGROW>
  p = p + 20;
end
end

function off = rvaToOffset(rva, sec)
i = find(rva >= sec(:,1) & rva < sec(:,1) + sec(:,2), 1);
assert(~isempty(i), 'RVA outside sections');
off = rva - sec(i,1) + sec(i,3);
end
