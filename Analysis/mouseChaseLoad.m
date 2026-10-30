function [m, folder] = mouseChaseLoad(source, root)
%MOUSECHASELOAD Load a MouseChaseTouch session log.
%   [M, FOLDER] = MOUSECHASELOAD(FILE) loads <expRef>_MouseChase.mat.
%   MOUSECHASELOAD(EXPREF) finds it in the experiment's folders: with
%   Rigbox on the path via dat.expPath, otherwise under ROOT (default
%   \\zenneth.cortexlab.net\Subjects) as ROOT\subject\date\seq.
%   MOUSECHASELOAD() asks for the file. M is the 'mouseChase' struct saved
%   by MouseChaseTouch; FOLDER is where it was found (block, Timeline and
%   camera files are next to it).

if nargin < 2 || isempty(root); root = '\\zenneth.cortexlab.net\Subjects'; end
if nargin < 1 || isempty(source)
  [f, d] = uigetfile('*_MouseChase.mat', 'Choose a MouseChase session log');
  if isequal(f, 0); m = []; folder = ''; return; end
  source = fullfile(d, f);
end
if ~exist(source, 'file') % an experiment reference: date_seq_subject
  ref = source;
  tok = regexp(ref, '^(\d{4}-\d{2}-\d{2})_(\d+)_(.+)$', 'tokens', 'once');
  assert(~isempty(tok), 'mouseChaseLoad:badRef', '"%s" is neither a file nor an experiment reference', ref);
  dirs = {fullfile(root, tok{3}, tok{1}, tok{2})};
  if exist('dat.expPath', 'file')
    dirs = [cellstr(dat.expPath(ref, 'main')); dirs];
  end
  files = fullfile(dirs, [ref '_MouseChase.mat']);
  found = find(cellfun(@(f) exist(f, 'file') == 2, files), 1);
  assert(~isempty(found), 'mouseChaseLoad:notFound', 'No %s_MouseChase.mat in %s', ref, strjoin(dirs, ', '));
  source = files{found};
end
folder = fileparts(source);
m = load(source, 'mouseChase');
m = m.mouseChase;
end
