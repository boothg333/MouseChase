function out = Screen(cmd, varargin)
switch cmd
  case 'Windows', out = 10;
  case 'WindowKind', out = 1;
  otherwise, error('fake Screen: %s', cmd);
end
end
