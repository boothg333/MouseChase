function evt = TouchEventGet(varargin)
global SIM
evt = SIM.queue(1);
SIM.queue(1) = [];
end
