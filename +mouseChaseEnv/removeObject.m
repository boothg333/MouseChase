function env = removeObject(env, idx)
%MOUSECHASEENV.REMOVEOBJECT Remove hiding object(s) by index (as numbered
%   in mouseChaseEnv.preview).
assert(all(idx >= 1 & idx <= numel(env.objects)), 'mouseChaseEnv:badIndex', ...
  'This environment has %d objects.', numel(env.objects));
env.objects(idx) = [];
end
