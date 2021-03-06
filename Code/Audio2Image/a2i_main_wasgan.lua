--[[
-- Modified from : Generative Adversarial Text-to-Image Synthesis
   Original source : https://github.com/reedscot/icml2016
   Author : MinHyung Kang, Chris Kymn

   Generic training script for GAN, GAN-CLS, GAN-INT, GAN-CLS-INT.
   Training script for audio-to-image synthesis
--]]
require 'torch'
require 'nn'
require 'nngraph'
require 'optim'
require 'cudnn'

opt = {
   numAudio = 1, -- Number of audio samples per image
   replicate = 0, -- TODO : Could change this (if 1, then replicate averaged text features numAudio times.)
   save_every = 10,
   print_every = 1,
   c = 0.01,               -- bound for weight clipping of the critic
   dataset = 'instruments',       -- imagenet / lsun / folder
   no_aug = 0,
   img_dir = './../../Data/ucf3_subset',
   keep_img_frac = 1.0,
   interp_weight = 1,
   interp_type = 1,
   cls_weight = 0.5,
   filenames = '',
   data_root = './../../Data/ucf3audio_subset',
   classnames = './../../Data/allclasses.txt',
   trainids = './../../Data/allids.txt',
   checkpoint_dir = '/checkpoints',
   numshot = 0,
   batchSize = 64,
   doc_length = 201,
   loadSize = 76,
   loadSizeX = 88,
   loadSizeY = 66,
   auxSize = 1024,         -- #  of dim for raw text.
   fineSize = 64,
   na = 128,               -- #  of dim for audio features.
   nz = 100,               -- #  of dim for Z
   ngf = 128,              -- #  of gen filters in first conv layer
   ndf = 64,               -- #  of discrim filters in first conv layer
   nThreads = 4,           -- #  of data loading threads to use
   niter = 50000,             -- #  of iter at starting learning rate
   lr = 0.0002,            -- initial learning rate for adam
   lr_decay = 0.5,            -- initial learning rate for adam
   decay_every = 50,
   beta1 = 0.5,            -- momentum term of adam
   ntrain = math.huge,     -- #  of examples per epoch. math.huge for full dataset
   display = 1,            -- display samples while training. 0 = false
   display_id = 10,        -- display window id.
   gpu = 2,                -- gpu = 0 is CPU mode. gpu=X is GPU mode on GPU X
   name = 'Every10_3class_a2i_wasgan_88by66',
   noise = 'normal',       -- uniform / normal
   init_g = '',
   init_d = '',
   use_cudnn = 1,
   ncritic = 5,            -- #  of training iterations of D for 1 iteration of G
}

-- one-line argument parser. parses enviroment variables to override the defaults
for k,v in pairs(opt) do opt[k] = tonumber(os.getenv(k)) or os.getenv(k) or opt[k] end
print(opt)
if opt.display == 0 then opt.display = false end

if opt.gpu > 0 then
   ok, cunn = pcall(require, 'cunn')
   ok2, cutorch = pcall(require, 'cutorch')
   cutorch.setDevice(opt.gpu)
end

opt.manualSeed = torch.random(1, 10000) -- fix seed
print("Random Seed: " .. opt.manualSeed)
torch.manualSeed(opt.manualSeed)
torch.setnumthreads(1)
torch.setdefaulttensortype('torch.FloatTensor')

-- create data loader
local DataLoader = paths.dofile('data/a2i_data.lua')
local data = DataLoader.new(opt.nThreads, opt.dataset, opt)
print("Dataset: " .. opt.dataset, " Size: ", data:size())
----------------------------------------------------------------------------

-- Init weights (convolutional layers vs batch normalization)
local function weights_init(m)
   local name = torch.type(m)
   if name:find('Convolution') then
      m.weight:normal(0.0, 0.02)
      m.bias:fill(0)
   elseif name:find('BatchNormalization') then
      if m.weight then m.weight:normal(1.0, 0.02) end
      if m.bias then m.bias:fill(0) end
   end
end

local nc = 3
local nz = opt.nz -- #  of dim for Z
local ndf = opt.ndf -- #  of discrim filters in first conv layer
local ngf = opt.ngf -- #  of gen filters in first conv layer
local real_label = 1
local fake_label = 0

local SpatialBatchNormalization = nn.SpatialBatchNormalization
local SpatialConvolution = nn.SpatialConvolution
local SpatialFullConvolution = nn.SpatialFullConvolution


-- Create generator network
if opt.init_g == '' then
    -- TODO : should be changed to sound features
    fcG = nn.Sequential()
    fcG:add(nn.Linear(opt.auxSize,opt.na)) -- Text to text features
    fcG:add(nn.LeakyReLU(0.2,true)) -- nonlinearity
    netG = nn.Sequential()
    -- concat Z and txt
    ptg = nn.ParallelTable()
    ptg:add(nn.Identity()) -- for noise
    ptg:add(fcG)
    netG:add(ptg) -- ptg contains : 1 identity, 1 fcG (Text to features)
    netG:add(nn.JoinTable(2)) -- Concatenates result along 2nd dimension
    -- input is Z, going into a convolution
    netG:add(SpatialFullConvolution(nz + opt.na, ngf * 8, 4, 4)) -- Kernel width, height = 4,4
    netG:add(SpatialBatchNormalization(ngf * 8))

      -- state size: (ngf*8) x 4 x 4
      local conc = nn.ConcatTable() -- Each member module to same input
      local conv = nn.Sequential()
      conv:add(SpatialConvolution(ngf * 8, ngf * 2, 1, 1, 1, 1, 0, 0))
      conv:add(SpatialBatchNormalization(ngf * 2)):add(nn.ReLU(true))
      conv:add(SpatialConvolution(ngf * 2, ngf * 2, 3, 3, 1, 1, 1, 1))
      conv:add(SpatialBatchNormalization(ngf * 2))

      conv:add(nn.ReLU(true))
      conv:add(SpatialConvolution(ngf * 2, ngf * 8, 3, 3, 1, 1, 1, 1))
      conv:add(SpatialBatchNormalization(ngf * 8))
      conc:add(nn.Identity())
      conc:add(conv)
      netG:add(conc)
      netG:add(nn.CAddTable())
      netG:add(nn.ReLU(true))

    -- state size: (ngf*8) x 4 x c
    netG:add(SpatialFullConvolution(ngf * 8, ngf * 4, 4, 4, 2, 2, 1, 1))
    netG:add(SpatialBatchNormalization(ngf * 4))

      -- state size: (ngf*4) x 8 x 8
      local conc = nn.ConcatTable()
      local conv = nn.Sequential()
      conv:add(SpatialConvolution(ngf * 4, ngf, 1, 1, 1, 1, 0, 0))
      conv:add(SpatialBatchNormalization(ngf)):add(nn.ReLU(true))
      conv:add(SpatialConvolution(ngf, ngf, 3, 3, 1, 1, 1, 1))
      conv:add(SpatialBatchNormalization(ngf))

      conv:add(nn.ReLU(true))
      conv:add(SpatialConvolution(ngf, ngf * 4, 3, 3, 1, 1, 1, 1))
      conv:add(SpatialBatchNormalization(ngf * 4))
      conc:add(nn.Identity())
      conc:add(conv)
      netG:add(conc)
      netG:add(nn.CAddTable())
      netG:add(nn.ReLU(true))

        -- state size: (ngf*4) x 8 x 8
    netG:add(SpatialFullConvolution(ngf * 4, ngf * 2, 4, 4, 2, 2, 1, 1))
    netG:add(SpatialBatchNormalization(ngf * 2)):add(nn.ReLU(true))

    -- state size: (ngf*2) x 16 x 16
    netG:add(SpatialFullConvolution(ngf * 2, ngf, 4, 4, 2, 2, 1, 1))
    netG:add(SpatialBatchNormalization(ngf)):add(nn.ReLU(true))

    -- state size: (ngf) x 32 x 32
    netG:add(SpatialFullConvolution(ngf, nc, 4, 4, 2, 2, 1, 1))
    netG:add(nn.Tanh())

    -- state size: (nc) x 64 x 64
    netG:apply(weights_init)
else -- There is already initialized G
  netG = torch.load(opt.init_g)
end

-- Discriminator
if opt.init_d == '' then
    convD = nn.Sequential()
    -- input is (nc) x 64 x 64 : Here it's 3 : probably rgb?
    convD:add(SpatialConvolution(nc, ndf, 4, 4, 2, 2, 1, 1))
    convD:add(nn.LeakyReLU(0.2, true))
    -- state size: (ndf) x 32 x 32
    convD:add(SpatialConvolution(ndf, ndf * 2, 4, 4, 2, 2, 1, 1))
    convD:add(SpatialBatchNormalization(ndf * 2)):add(nn.LeakyReLU(0.2, true))
    -- state size: (ndf*2) x 16 x 16
    convD:add(SpatialConvolution(ndf * 2, ndf * 4, 4, 4, 2, 2, 1, 1))
    convD:add(SpatialBatchNormalization(ndf * 4))

    -- state size: (ndf*4) x 8 x 8
    convD:add(SpatialConvolution(ndf * 4, ndf * 8, 4, 4, 2, 2, 1, 1))
    convD:add(SpatialBatchNormalization(ndf * 8))

      -- state size: (ndf*8) x 4 x 4
      local conc = nn.ConcatTable()
      local conv = nn.Sequential()
      conv:add(SpatialConvolution(ndf * 8, ndf * 2, 1, 1, 1, 1, 0, 0))
      conv:add(SpatialBatchNormalization(ndf * 2)):add(nn.LeakyReLU(0.2, true))
      -- state size : (ndf * 2) x 4 x 4
      conv:add(SpatialConvolution(ndf * 2, ndf * 2, 3, 3, 1, 1, 1, 1))
      conv:add(SpatialBatchNormalization(ndf * 2))
      conv:add(nn.LeakyReLU(0.2, true))
      -- state size : (ndf * 2) x 4 x 4
      conv:add(SpatialConvolution(ndf * 2, ndf * 8, 3, 3, 1, 1, 1, 1))
      conv:add(SpatialBatchNormalization(ndf * 8))
      -- state size : (ndf * 8) x 4 x 4
      conc:add(nn.Identity())
      conc:add(conv)
      convD:add(conc)
      convD:add(nn.CAddTable())
      convD:add(nn.LeakyReLU(0.2, true))

      -- TODO : Takes input as text (should be changed to sound)
    local fcD = nn.Sequential()
    fcD:add(nn.Linear(opt.auxSize,opt.na))
    fcD:add(nn.BatchNormalization(opt.na))
    fcD:add(nn.LeakyReLU(0.2,true))
    fcD:add(nn.Replicate(4,3))
    fcD:add(nn.Replicate(4,4))
    netD = nn.Sequential()
    pt = nn.ParallelTable()
    pt:add(convD)
    pt:add(fcD)
    netD:add(pt)
    netD:add(nn.JoinTable(2))
    -- state size: (ndf*8 + 128) x 4 x 4
    netD:add(SpatialConvolution(ndf * 8 + opt.na, ndf * 8, 1, 1)) -- filters of (Text + features from img) combined
    netD:add(SpatialBatchNormalization(ndf * 8)):add(nn.LeakyReLU(0.2, true))
    -- state size: (ndf*8) x 4 x 4
    netD:add(SpatialConvolution(ndf * 8, 1, 4, 4)) -- One final layer
    netD:add(nn.Sigmoid()) -- Scalar, probability
    -- state size: 1 x 1 x 1
    netD:add(nn.View(1):setNumInputDims(3))
    -- state size: 1
    netD:apply(weights_init)
else -- pretrained model
  netD = torch.load(opt.init_d)
end
-- Check batchsize is divisible by number of captions.
assert(math.floor(opt.batchSize / opt.numAudio) * opt.numAudio == opt.batchSize)
netR = nn.Sequential()
if opt.replicate == 1 then -- Hmm? Take average of opt.numAudio amount in batches, repeat?
  netR:add(nn.Reshape(opt.batchSize / opt.numAudio, opt.numAudio, opt.auxSize))
  netR:add(nn.Transpose({1,2}))
  netR:add(nn.Mean(1))
  netR:add(nn.Replicate(opt.numAudio))
  netR:add(nn.Transpose({1,2}))
  netR:add(nn.Reshape(opt.batchSize, opt.auxSize))
else
  netR:add(nn.Reshape(opt.batchSize, opt.numAudio, opt.auxSize))
  netR:add(nn.Transpose({1,2}))
  netR:add(nn.Mean(1))
end

local criterion = nn.BCECriterion()
local weights = torch.zeros(opt.batchSize * 3/2)
weights:narrow(1,1,opt.batchSize):fill(1)
weights:narrow(1,opt.batchSize+1,opt.batchSize/2):fill(opt.interp_weight)
local criterion_interp = nn.BCECriterion(weights)
---------------------------------------------------------------------------
optimStateG = {
   learningRate = opt.lr,
   beta1 = opt.beta1,
}
optimStateD = {
   learningRate = opt.lr,
   beta1 = opt.beta1,
}
----------------------------------------------------------------------------
--[[
local alphabet = "abcdefghijklmnopqrstuvwxyz0123456789-,;.!?:'\"/\\|_@#$%^&*~`+-=<>()[]{} "
alphabet_size = #alphabet
--]]
local input_img = torch.Tensor(opt.batchSize, 3, opt.fineSize, opt.fineSize)
-- Interpolation
local input_img_interp = torch.Tensor(opt.batchSize * 3/2, 3, opt.fineSize, opt.fineSize)
if opt.replicate == 1 then
  input_aux_raw = torch.Tensor(opt.batchSize, opt.auxSize)
else
  input_aux_raw = torch.Tensor(opt.batchSize * opt.numAudio, opt.auxSize)
end
local input_aux = torch.Tensor(opt.batchSize, opt.auxSize)
local input_aux_interp = torch.zeros(opt.batchSize * 3/2, opt.auxSize)
local noise = torch.Tensor(opt.batchSize, nz, 1, 1)
local noise_interp = torch.Tensor(opt.batchSize * 3/2, nz, 1, 1)
local label = torch.Tensor(opt.batchSize)
local label_interp = torch.Tensor(opt.batchSize * 3/2)
local stats = torch.zeros(opt.niter,5)
local errD, errG, errW
local epoch_tm = torch.Timer()
local tm = torch.Timer()
local data_tm = torch.Timer()

local real_label = 1
local fake_label = -1
----------------------------------------------------------------------------
if opt.gpu > 0 then
   input_img = input_img:cuda()
   input_img_interp = input_img_interp:cuda()
   input_aux = input_aux:cuda()
   input_aux_raw = input_aux_raw:cuda()
   input_aux_interp = input_aux_interp:cuda()
   noise = noise:cuda()
   noise_interp = noise_interp:cuda()
   label = label:cuda()
   label_interp = label_interp:cuda()
   netD:cuda()
   netG:cuda()
   netR:cuda()
   criterion:cuda()
   criterion_interp:cuda()
end

if opt.use_cudnn == 1 then
  cudnn = require('cudnn')
  netD = cudnn.convert(netD, cudnn)
  netG = cudnn.convert(netG, cudnn)
  netR = cudnn.convert(netR, cudnn)
end

local parametersD, gradParametersD = netD:getParameters()
local parametersG, gradParametersG = netG:getParameters()

if opt.display then disp = require 'display' end

-- create closure to evaluate f(X) and df/dX of discriminator
local fDx = function(x)
  netD:apply(function(m) if torch.type(m):find('Convolution') and m.bias ~= nil then m.bias:zero() end end)
  netG:apply(function(m) if torch.type(m):find('Convolution') and m.bias ~= nil then m.bias:zero() end end)

  gradParametersD:zero()
     -- clamp parameters
  parametersD:clamp(-opt.c, opt.c)

  -- train with real
  data_tm:reset(); data_tm:resume()
  real_img, real_aux, wrong_img, _ = data:getBatch()
  data_tm:stop()

  input_img:copy(real_img)
  input_aux_raw:copy(real_aux)

  -----------------------------------------------------------
  -- average adjacent text features in batch dimension.
  emb_aux = netR:forward(input_aux_raw)
  input_aux:copy(emb_aux)

  if opt.interp_type == 1 then -- This works well
    -- compute (a + b)/2
    input_aux_interp:narrow(1,1,opt.batchSize):copy(input_aux)
    input_aux_interp:narrow(1,opt.batchSize+1,opt.batchSize/2):copy(input_aux:narrow(1,1,opt.batchSize/2))
    input_aux_interp:narrow(1,opt.batchSize+1,opt.batchSize/2):add(input_aux:narrow(1,opt.batchSize/2+1,opt.batchSize/2))
    input_aux_interp:narrow(1,opt.batchSize+1,opt.batchSize/2):mul(0.5)
  elseif opt.interp_type == 2 then
    -- compute (a + b)/2
    input_aux_interp:narrow(1,1,opt.batchSize):copy(input_aux)
    input_aux_interp:narrow(1,opt.batchSize+1,opt.batchSize/2):copy(input_aux:narrow(1,1,opt.batchSize/2))
    input_aux_interp:narrow(1,opt.batchSize+1,opt.batchSize/2):add(input_aux:narrow(1,opt.batchSize/2+1,opt.batchSize/2))
    input_aux_interp:narrow(1,opt.batchSize+1,opt.batchSize/2):mul(0.5)

    -- add extrapolation vector.
    local alpha = torch.rand(opt.batchSize/2,1):mul(2):add(-1) -- alpha ~ uniform(-1,1)
    if opt.gpu >=0 then
     alpha = alpha:float():cuda()
    end
    alpha = torch.expand(alpha,opt.batchSize/2,input_aux_interp:size(2))
    local vec = (input_aux:narrow(1,opt.batchSize/2+1,opt.batchSize/2) -
                input_aux:narrow(1,1,opt.batchSize/2)):cmul(alpha) -- elementwise multiplication
    input_aux_interp:narrow(1,opt.batchSize+1,opt.batchSize/2):add(vec)
  end
  label:fill(real_label)
   ------------------------^^^^^^^^^^^^^^^^------------------------

  errD_real = netD:forward{input_img, input_aux}
  errD_real = errD_real:mean()
  netD:backward({input_img, input_aux}, label)

  errD_wrong = 0
  if opt.cls_weight > 0 then
    -- train with wrong image-aux pair
    input_img:copy(wrong_img)
    label:fill(fake_label)

    errD_wrong = netD:forward{input_img, input_aux}
    errD_wrong = opt.cls_weight * errD_wrong:mean() 
    netD:backward({input_img, input_aux}, label)
  end

  -- train with fake
  if opt.noise == 'uniform' then -- regenerate random noise
    noise:uniform(-1, 1)
  elseif opt.noise == 'normal' then
    noise:normal(0, 1)
  end
  local fake = netG:forward{noise, input_aux}
  input_img:copy(fake)
  label:fill(fake_label)

  errD_fake = netD:forward{input_img, input_aux}
  errD_fake = errD_fake:mean()
  netD:backward({input_img, input_aux},label)

  errD = errD_real - errD_fake - errD_wrong
  errW = errD_wrong

  return errD, gradParametersD
end

-- create closure to evaluate f(X) and df/dX of generator
local fGx = function(x)
  netD:apply(function(m) if torch.type(m):find('Convolution') and m.bias ~= nil then m.bias:zero() end end)
  netG:apply(function(m) if torch.type(m):find('Convolution') and m.bias ~= nil then m.bias:zero() end end)

  gradParametersG:zero()

  if opt.noise == 'uniform' then -- regenerate random noise
    noise_interp:uniform(-1, 1)
  elseif opt.noise == 'normal' then
    noise_interp:normal(0, 1)
  end
  local fake = netG:forward{noise_interp, input_aux_interp}
  input_img_interp:copy(fake)
  label_interp:fill(real_label) -- fake labels are real for generator cost

  local output = netD:forward{input_img_interp, input_aux_interp}
  errG = criterion_interp:forward(output, label_interp)
  local df_do = criterion_interp:backward(output, label_interp)
  local df_dg = netD:updateGradInput({input_img_interp, input_aux_interp}, df_do)

  netG:backward({noise_interp, input_aux_interp}, df_dg[1])
  return errG, gradParametersG
end

-- train
local counter = 0
local statIndex = 1

for epoch = 1, opt.niter do
  epoch_tm:reset()
  local i = 1
  local len_dataloader = math.floor(math.min(data:size(), opt.ntrain), opt.batchSize/opt.batchSize)
  if epoch % opt.decay_every == 0 then
    optimStateG.learningRate = optimStateG.learningRate * opt.lr_decay
    optimStateD.learningRate = optimStateD.learningRate * opt.lr_decay
  end

  while i <= len_dataloader do
    tm:reset()
    local Diter
    if counter <= 25 then
        Diter = 25
    else
        Diter = opt.ncritic
    end

    -- (1) Update D network: maximize log(D(x)) + log(1 - D(G(z)))
    for j = 1, Diter do
        optim.rmsprop(fDx, parametersD, optimStateD)
    end

    i = i + Diter

    -- (2) Update G network: maximize log(D(G(z)))
    optim.adam(fGx, parametersG, optimStateG)

    counter = counter + 1
    -- logging

    printString = ('[%d][%d/%d] T:%.3f  DT:%.3f lr: %.4g '
              .. '  Err_G: %.4f  Err_D: %.4f Err_W: %.4f'):format(
            epoch, ((i-1) / opt.batchSize),
            math.floor(math.min(data:size(), opt.ntrain) / opt.batchSize),
            tm:time().real, data_tm:time().real,
            optimStateG.learningRate,
            errG and errG or -1, errD and errD or -1,
            errW and errW or -1)
    print(printString)
  end

  stats[statIndex][1] = epoch
  stats[statIndex][2] = optimStateG.learningRate
  stats[statIndex][3] = errG and errG or -1
  stats[statIndex][4] = errD and errD or -1
  stats[statIndex][5] = errW and errW or -1

  statIndex = statIndex + 1

  if epoch % opt.save_every == 0 then
    paths.mkdir(opt.checkpoint_dir)

    print('Saving at ' ..opt.checkpoint_dir)
    torch.save(opt.checkpoint_dir .. '/' .. opt.name .. '_' .. epoch .. '_net_G.t7', netG)
    torch.save(opt.checkpoint_dir .. '/' .. opt.name .. '_' .. epoch .. '_net_D.t7', netD)
    torch.save(opt.checkpoint_dir .. '/' .. opt.name .. '_' .. epoch .. '_opt.t7', opt)
    torch.save(opt.checkpoint_dir .. '/' .. opt.name .. '_' .. epoch .. '_stats.t7',stats)
    print(('End of epoch %d / %d \t Time Taken: %.3f'):format(
           epoch, opt.niter, epoch_tm:time().real))
  end
end
