%% Test Linear Regression and Word2Vec Embedding
%
%   varargin - {1} perc_TrainingSet, {2} cluster_type - the technique used for
%   Kmeans, {3} nSample - the number of samples for generating codebook, {4}
%   CodebookSize - the number of centers for Kmeans, varargin{5} - preprocess of
%   dataset: org (original video) or sta (stabilized video), varargin{6] -
%   featuretype, varargin{7} - do pca on input data, if 0 don't do pca if
%   nonzero, do pca and take the first # varargin{7} dims as the process
%   training data.
%   rbdchisq kernel is applied
%   Self-training is applied to drift prototypes
%

function [meanAcc,Accuracy] = func_ts_ZSL_KmeansLLM(Para,Model)

global D;

addpath('/import/geb-experiments/Alex/CVPR15/Code/Zeroshot/HMDBregression/Code/Basic/FVNormalization');
addpath('/import/geb-experiments/Alex/ICCV15/code/TransferRegression/CollectData/function');
addpath('/import/geb-experiments/Alex/ICCV15/code/SharedTools/function/');


%% Assign test instances to clusters
aug_tr_idx = Para.selected_tr_idx;
selected_ts_idx = Para.selected_ts_idx;
K_ts_tr = D(selected_ts_idx,aug_tr_idx);
N_K = numel(aug_tr_idx);
ts_idx=knnsearch(Model.Center(:,1:N_K),K_ts_tr,'distance','cosine');
for llm_i = 1:Para.NumLLM
    ts_llm_idx = ts_idx == llm_i;
    tr_idx = Model.TrClusterIdx == llm_i;
    S_ts(:,ts_llm_idx) = Model.A{llm_i}*K_ts_tr(ts_llm_idx,tr_idx)';
end

S_ts = func_L2Normalization(S_ts)';

%% Knn to predict final labels

ts_ClassNo = Para.ClassNoPerVideo(Para.ts_sample_ind);

%%% Generate Prototypes
Prototype = func_L2Normalization(Para.phrasevec_mat(Para.idx_TestingSet,:));
% Prototype = (pinv(S)*Prototype')';

if Para.SelfTraining
    %% Self-training
    parfor K = 1:200;
        stPrototype = func_SelfTraining(Prototype, S_ts, K);
        
        stPrototype = func_SelfTraining(stPrototype, S_ts, K);

        
        %%% Predict labels
        predict_ClassNo = knnsearch(stPrototype,S_ts,'Distance','cosine');
        
        %%% Calculate Average Precision for each Class
        Accuracy = zeros(1,length(idx_TestingSet));
        for c_ts = 1:length(idx_TestingSet)
            
            currentClass = idx_TestingSet(c_ts);
            currentClass_SampleIndex = ts_ClassNo==currentClass;
            currentClass_Predict = predict_ClassNo(currentClass_SampleIndex);   % predicted class no
            Accuracy(c_ts) = sum(currentClass_Predict == c_ts)/length(currentClass_Predict);
            
        end
        
        meanAcc(K) = mean(Accuracy);
    end
else
    %%% Predict labels
    predict_ClassNo = knnsearch(Prototype,S_ts,'Distance','cosine');
    
    %%% Calculate Average Precision for each Class
    for c_ts = 1:length(Para.idx_TestingSet)
        
        currentClass = Para.idx_TestingSet(c_ts);
        currentClass_SampleIndex = ts_ClassNo==currentClass;
        currentClass_Predict = predict_ClassNo(currentClass_SampleIndex);   % predicted class no
        Accuracy(1,c_ts) = sum(currentClass_Predict == c_ts)/length(currentClass_Predict);
        
    end
    
    meanAcc = mean(Accuracy);
end

% meanAcc = max(meanAcc);

function [stPrototypes] = func_SelfTraining(Prototype, LabelVector, K)
%% Do self-training on prototypes
%
%   Prototypes moves towards the K

IDX = knnsearch(LabelVector,Prototype,'Distance','euclidean','K',K);

for p_i = 1:size(Prototype,1)
    stPrototypes(p_i,:) = mean(LabelVector(IDX(p_i,:),:),1);
end

function stPrototypes = func_SelfTraining_Median(Prototype, LabelVector, K)
%% Do median self-training on prototypes
%
%   Prototypes moves towards the K

[IDX,D] = knnsearch(LabelVector,Prototype,'Distance','euclidean','K',K);

for p_i = 1:size(Prototype,1)
    idx = round(K/2);
    stPrototypes(p_i,:) = LabelVector(IDX(p_i,idx),:);
end
