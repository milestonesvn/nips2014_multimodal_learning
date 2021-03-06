% -------------------------------------------------------------------------
% Classification pipeline for layer-2 image pathway on Flickr
%   using binary-binary RBM
%
%   dotest (1/0), foldlist (1:5), optgpu (1/0),
%   numhid      : number of latent variables
%   numstep_h   : number of stepped sigmoid units, >= 1
%   epsilon     : learning rate
%   sp_reg      : sparsity regularization weight
%   sp_target   : sparsity target, >= 0, <= 1
%   l2reg       : l2 weight decay weight
%   kcd         : number of CD steps, >= 1
%   maxiter     : max epoch
%   batchsize   : mini-batch size
%   stdinit     : initialization weight (std of gaussian)
%   upfactor    : multiplier for hidden unit inference
%   downfactor  : multiplier for visible unit inference
%       (same applies to param"2")
%
%   written by Kihyuk Sohn
% -------------------------------------------------------------------------

function [net, map_val, map_test] = flickr_img_l2(dotest, foldlist, optgpu, ...
    numhid, numstep_h, epsilon, sp_reg, sp_target, l2reg, kcd, maxiter, batchsize, stdinit, upfactor, downfactor, ...
    numhid2, numstep_h2, epsilon2, sp_reg2, sp_target2, l2reg2, kcd2, maxiter2, batchsize2, stdinit2, upfactor2, downfactor2)

startup;
l2reg_list = [1e-3 3e-3 1e-2 3e-2 1e-1]; % cross validation


% -------------------------------------------------------------------------
%                                                    initialize variables
% -------------------------------------------------------------------------

if ~exist('dotest', 'var'),
    dotest = 1;
end
if ~exist('foldlist', 'var') || isempty(foldlist),
    foldlist = 1:5;
end
if ~exist('optgpu', 'var'),
    optgpu = 1;
end

% input-output types
typein = 'real';    % replicated-softmax
typeout = 'step';   % stepped sigmoid

typein2 = 'binary';
typeout2 = 'binary';


% first layer
if ~exist('numhid', 'var'),
    numhid = 1024;
end
if ~exist('numstep_h', 'var'),
    numstep_h = 5;
end
if ~exist('epsilon', 'var'),
    epsilon = 0.001;
end
if ~exist('sp_reg', 'var'),
    sp_reg = 1;
end
if ~exist('sp_target', 'var'),
    sp_target = 0.2;
end
if ~exist('l2reg', 'var'),
    l2reg = 1e-5;
end
if ~exist('kcd', 'var'),
    kcd = 1;
end
if ~exist('maxiter', 'var'),
    maxiter = 300;
end
if ~exist('batchsize', 'var'),
    batchsize = 100;
end
if ~exist('stdinit', 'var'),
    stdinit = 0.005;
end
if ~exist('upfactor', 'var'),
    upfactor = 2;
end
if ~exist('downfactor', 'var'),
    downfactor = 1;
end

% second layer
if ~exist('numhid2', 'var'),
    numhid2 = 512;
end
if ~exist('numstep_h2', 'var'),
    numstep_h2 = 5;
end
if ~exist('epsilon2', 'var'),
    epsilon2 = 0.1;
end
if ~exist('sp_reg2', 'var'),
    sp_reg2 = 0.1;
end
if ~exist('sp_target2', 'var'),
    sp_target2 = 0.2;
end
if ~exist('l2reg2', 'var'),
    l2reg2 = 1e-5;
end
if ~exist('kcd2', 'var'),
    kcd2 = 1;
end
if ~exist('maxiter2', 'var'),
    maxiter2 = 100;
end
if ~exist('batchsize2', 'var'),
    batchsize2 = 200;
end
if ~exist('stdinit2', 'var'),
    stdinit2 = 0.01;
end
if ~exist('upfactor2', 'var'),
    upfactor2 = 2;
end
if ~exist('downfactor2', 'var'),
    downfactor2 = 2;
end

dataset = 'flickr_img';
net = cell(2, 1);


% -------------------------------------------------------------------------
%                          train gaussian-stepped sigmoid RBM (1st layer)
% -------------------------------------------------------------------------

params = struct(...
    'dataset', dataset, ...
    'optgpu', optgpu, ...
    'savedir', savedir, ...
    'typein', typein, ...
    'typeout', typeout, ...
    'numvis', 3857, ...
    'numhid', numhid, ...
    'numstep_h', numstep_h, ...
    'eps', epsilon, ...
    'eps_decay', 0.01, ...
    'sp_type', 'approx', ...
    'sp_reg', sp_reg, ...
    'sp_target', sp_target, ...
    'l2reg', l2reg, ...
    'usepcd', 0, ...
    'kcd', kcd, ...
    'maxiter', maxiter, ...
    'saveiter', maxiter, ...
    'batchsize', batchsize, ...
    'normalize', false, ...
    'stdinit', stdinit, ...
    'std_learn', 0, ...
    'momentum_change', 5, ...
    'momentum_init', 0.33, ...
    'momentum_final', 0.5, ...
    'upfactor', upfactor, ...
    'downfactor', downfactor);

params = fillin_params(params);

params.fname = sprintf('%s_%s_%s_v_%d_h_%d_step_%d_eps_%g_l2r_%g_%s_target_%g_reg_%g_pcd_%d_kcd_%d_bs_%d_init_%g_up_%d_down_%d', ...
    params.dataset, params.typein, params.typeout, params.numvis, params.numhid, ...
    params.numstep_h, params.eps, params.l2reg, params.sp_type, params.sp_target, params.sp_reg, ...
    params.usepcd, params.kcd, params.batchsize, params.stdinit, params.upfactor, params.downfactor);


% load mean and std for global preprocessing
[m_global, stds_global] = compute_mean_std(0, 10000);
try
    load(sprintf('%s/%s_iter_%d.mat', savedir, params.fname, params.maxiter), 'weights', 'params');
    fprintf('load first layer image dictionary\n');
catch
    % load data
    [xunlab, numdim_img] = load_flickr_unlab(0, 2000);
    xunlab = xunlab(1:numdim_img, :);
    
    % preprocessing
    xunlab = bsxfun(@rdivide, bsxfun(@minus, xunlab, m_global), stds_global);
    
    [weights, params, history] = rbm_train(xunlab, params);
    save(sprintf('%s/%s_iter_%d.mat', savedir, params.fname, params.maxiter), 'weights', 'params', 'history');
    
    clear xunlab;
end

fname = sprintf('%s_iter_%d', params.fname, maxiter);
[~, infer] = rbm_infer(weights, params);

net{1}.weights = weights;
net{1}.params = params;
net{1}.infer = infer;

savedir = sprintf('%s/%s', savedir, fname);
if ~exist(savedir, 'dir'),
    mkdir(savedir);
end

clear weights params history;


% -------------------------------------------------------------------------
%                                     train binary-binary RBM (2nd layer)
% -------------------------------------------------------------------------

params = struct(...
    'dataset', sprintf('%s_l2', dataset), ...
    'optgpu', optgpu, ...
    'savedir', savedir, ...
    'typein', typein2, ...
    'typeout', typeout2, ...
    'numvis', net{1}.params.numhid, ...
    'numhid', numhid2, ...
    'numstep_h', numstep_h2, ...
    'eps', epsilon2, ...
    'eps_decay', 0.01, ...
    'sp_type', 'approx', ...
    'sp_reg', sp_reg2, ...
    'sp_target', sp_target2, ...
    'l2reg', l2reg2, ...
    'usepcd', 1, ...
    'negchain', 500, ...
    'kcd', kcd2, ...
    'maxiter', maxiter2, ...
    'saveiter', maxiter2, ...
    'batchsize', batchsize2, ...
    'normalize', false, ...
    'stdinit', stdinit2, ...
    'std_learn', 0, ...
    'draw_sample', 1, ...
    'momentum_change', 5, ...
    'momentum_init', 0.33, ...
    'momentum_final', 0.5, ...
    'upfactor', upfactor2, ...
    'downfactor', downfactor2);

params = fillin_params(params);

params.fname = sprintf('%s_%s_%s_v_%d_h_%d_step_%d_%d_eps_%g_l2r_%g_%s_target_%g_reg_%g_pcd_%d_kcd_%d_bs_%d_init_%g_draw_%d_up_%d_down_%d', ...
    params.dataset, params.typein, params.typeout, params.numvis, params.numhid, ...
    params.numstep_v, params.numstep_h, params.eps, params.l2reg, params.sp_type, ...
    params.sp_target, params.sp_reg, params.usepcd, params.kcd, params.batchsize, ...
    params.stdinit, params.draw_sample, params.upfactor, params.downfactor);

try
    load(sprintf('%s/%s_iter_%d.mat', savedir, params.fname, params.maxiter), 'weights', 'params');
    fprintf('load second layer image dictionary\n');
catch
    % load data
    [xunlab, numdim_img] = load_flickr_unlab(0, 2000);
    xunlab = xunlab(1:numdim_img, :);
    
    % preprocessing & inference
    xunlab = bsxfun(@rdivide, bsxfun(@minus, xunlab, m_global), stds_global);
    xunlab = single(xunlab); % make sure single precision for memory efficiency
    xunlab = net{1}.infer(xunlab);
    
    % rbm training
    [weights, params, history] = rbm_train(xunlab, params);
    save(sprintf('%s/%s_iter_%d.mat', savedir, params.fname, params.maxiter), 'weights', 'params', 'history');
    
    clear xunlab;
end

fname = sprintf('%s_iter_%d', params.fname, params.maxiter);
[~, infer] = rbm_infer(weights, params);

net{2}.weights = weights;
net{2}.params = params;
net{2}.infer = infer;

clear weights params history;


% -------------------------------------------------------------------------
%                               test with multi-label logistic classifier
% -------------------------------------------------------------------------

if dotest,
    [xlab, ylab, folds, numdim_img, ~, ~] = load_flickr_lab;
    xlab = xlab(1:numdim_img, :);
    
    % preprocessing & inference
    xlab = bsxfun(@rdivide, bsxfun(@minus, xlab, m_global), stds_global);
    xlab = net{1}.infer(xlab);
    xlab = net{2}.infer(xlab);
    
    % run multiclass logistic regression
    [map_val, map_test] = run_mclr(xlab, '', ylab, folds, foldlist, l2reg_list, logdir, dataset, fname);
else
    map_val = -1;
    map_test = -1;
end

return;
