function copied = copyMouseChaseLogs(subjects, dryRun)
%COPYMOUSECHASELOGS Make sure MouseChase session logs are on the server.
%   MouseChaseTouch saves <expRef>_MouseChase.mat at the end of a session
%   both locally and on the main server (next to the block file). If the
%   server couldn't be reached then, only the local copy exists. This copies
%   any local _MouseChase.mat that is missing on the server, or newer than
%   the server's copy. Nothing is deleted.
%
%   COPYMOUSECHASELOGS() checks all subjects in the local repository.
%   COPYMOUSECHASELOGS(SUBJECTS) checks only these (char or cell array).
%   COPYMOUSECHASELOGS(SUBJECTS, true) only lists what would be copied.
%   COPIED = ... returns the server paths of the copied files.
%
%   Run on the stimulus PC (e.g. after a session), with Rigbox on the path.

if nargin < 1 || isempty(subjects)
  subjects = {};
end
if nargin < 2; dryRun = false; end
subjects = cellstr(subjects);
p = dat.paths;
localRoot = p.localRepository;
serverRoot = p.mainRepository;
fprintf('Local:  %s\nServer: %s\n', localRoot, serverRoot);
if isempty(subjects)
  d = dir(localRoot);
  subjects = {d([d.isdir] & ~startsWith({d.name}, '.')).name};
end

copied = {};
nChecked = 0;
for s = subjects
  files = dir(fullfile(localRoot, s{1}, '**', '*_MouseChase.mat'));
  for k = 1:numel(files)
    nChecked = nChecked + 1;
    src = fullfile(files(k).folder, files(k).name);
    destDir = [serverRoot, files(k).folder(numel(localRoot)+1:end)];
    dest = fullfile(destDir, files(k).name);
    onServer = dir(dest);
    if ~isempty(onServer) && onServer.datenum >= files(k).datenum
      continue % already there and up to date
    end
    if dryRun
      fprintf('Would copy %s\n        to %s\n', src, dest);
      copied{end+1} = dest; %#ok<AGROW>
      continue
    end
    if ~exist(destDir, 'dir'); mkdir(destDir); end
    [ok, msg] = copyfile(src, dest);
    if ok
      fprintf('Copied %s\n    to %s\n', src, dest);
      copied{end+1} = dest; %#ok<AGROW>
    else
      warning('copyMouseChaseLogs:failed', 'Could not copy %s: %s', src, msg);
    end
  end
end
fprintf('%d MouseChase log(s) checked, %d %s.\n', nChecked, numel(copied), ...
  iff(dryRun, 'would be copied', 'copied'));
end
