function [sRmse, sMae] = utkNc(seed, params)

%% Set random seed
rng(seed);

%% Load data
load(params.dataPath);

%% Create bins
c = 1:40;
s = 5;
centroids = [c(1:s:end)', c(2:s:end)', c(3:s:end)', c(4:s:end)', c(5:s:end)'];
centroids = [zeros(1, 5); centroids; 41 * ones(1, 5)];

%% Create discretization

N = size(centroids, 1);
M = size(centroids, 2);
[binnedTrainLabels, binnedestLabels] = ...
  centroidDiscretizations(double(trainLabels), centroids, N, M, double(testLabels));

%% Create new datastores

trainTable = table(train{:,1}, squeeze(binnedTrainLabels)');
testTable = table(test{:,1}, squeeze(binnedestLabels)');

outputSize = [224, 224];
aug = imageDataAugmenter('RandXReflection', true, 'RandXTranslation', [-20,20], ...
  'RandYTranslation', [-20,20], 'RandRotation', [0, 0], 'RandScale', [0.7, 1.4]);
binnedTrainDs = augmentedImageDatastore(outputSize, trainTable, 'ColorPreprocessing', 'gray2rgb', ...
  'DataAugmentation', aug);
binnedTestDs = augmentedImageDatastore(outputSize, testTable, 'ColorPreprocessing', 'gray2rgb');


%% Create ResNet
net = resnet50;
net = layerGraph(net);
net = removeLayers(net, 'fc1000');
net = removeLayers(net, 'fc1000_softmax');
net = removeLayers(net, 'ClassificationLayer_fc1000');

net = addLayers(net, fullyConnectedLayer(2048, 'name', 'fc2048'));
net = addLayers(net, reluLayer('name', 'relu'));
net = connectLayers(net, 'avg_pool', 'fc2048');
net = connectLayers(net, 'fc2048', 'relu');

net = addLayers(net, concatenationLayer(3,M,'Name','concat'));

for m = 1:M
  namefc = ['fc', num2str(m)];
  fc = fullyConnectedLayer(N, 'name', namefc);
  namesm = ['sm', num2str(m)];
  sm = customSoftmaxLayer(namesm);
  
  net = addLayers(net, fc);
  net = addLayers(net, sm);
  
  net = connectLayers(net, 'relu', namefc);
  net = connectLayers(net, namefc, namesm);
  
  net = connectLayers(net, namesm, ['concat/in', num2str(m)]);
  
end

net = addLayers(net, ncCrossEntropyLayer('ce', params.lambda, centroids, params.weights));
net = connectLayers(net, 'concat', 'ce');

%% Training parameters

options = trainingOptions(params.optimizer, ...
        'MiniBatchSize', params.miniBatchSize, ...
        'MaxEpochs', params.maxEpochs, ...
        'InitialLearnRate', params.lr, ...
        'LearnRateSchedule','piecewise', ...
        'LearnRateDropFactor', params.lrDropRate, ...
        'LearnRateDropPeriod', params.lrDropPeriod, ...
        'Shuffle','every-epoch', ...
        'Plots','none', ...
        'L2Regularization', params.L2reg, ...
        'VerboseFrequency', 300, ...
        'ValidationData', binnedTestDs, ...
        'ValidationFrequency', params.validationFreq, ...
        'ValidationPatience', Inf);

%% Train

[net, trainInfo] = trainNetwork(binnedTrainDs, net, options);

%% Prediction
pred = predict(net, testDs);

%% Equal weighting prediction

YPredicted = zeros(length(pred), 1);
for i =1:length(YPredicted)
  currY = pred(i, :);
  currY = reshape(currY, [N, M]);
  YPredicted(i) = mean(sum(centroids .* currY));
end

%% Show results
rmse = rms(double(YPredicted)-double(testLabels));
mae = mean(abs(double(YPredicted)-double(testLabels)));
sRmse = ['Test RMSE, ', num2str(rmse)];
sMae = ['Test MAE, ', num2str(mae)];
disp(sRmse);
disp(sMae);

%save('nc_lambda');
end
