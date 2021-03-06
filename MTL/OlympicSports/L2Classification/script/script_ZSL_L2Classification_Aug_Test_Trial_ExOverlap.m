%% script to run 50 indepedent datasplits for ZSL
clear;

global D idx_HMDB51 idx_UCF101 idx_OlympicSports idx_CCV tr_LabelVec_HMDB51 tr_LabelVec_UCF101 tr_LabelVec_OlympicSports tr_LabelVec_CCV;

addpath('../function');
addpath('/import/geb-experiments/Alex/ECCV16/code/MTL/SharedTools/function');

perc_TrainingSet = 0.5;
perc_TestingSet = 1 - perc_TrainingSet;
cluster_type = 'vlfeat';
nSample = 256000;
CodebookSize = 128;
process = 'org'; % preprocess of dataset: org,sta
FEATURETYPE = 'HOF|HOG|MBH';
nPCA = 0;
C = 2^1; % Cost parameter for SVR
SelfTraining = 0;   % Indicator if do selftraining
trial = 1;
EmbeddingMethod = 'add';

lambda_range = [1e1 1e0 1e-1 1e-2];
gamma_range = [1e1 1e0 1e-1 1e-2];
lambda_range = [1e1 5e0 1e0 1e-1 1e-2];
gamma_range = [1e1 5e0 1e0 1e-1 1e-2];

alpha = 0.2;
Para.SelfTraining = 0;

%% Internal Parameters
feature_data_base_path = '/import/geb-experiments-archive/Alex/OlympicSports/FV_ITF/';
zeroshot_base_path = '/import/geb-experiments-archive/Alex/OlympicSports/FV_ITF/Model/Zeroshot/jointcodebook/Embedding/';
if ~exist(zeroshot_base_path,'dir')
    mkdir(zeroshot_base_path);
end

datasplit_path = '/import/geb-experiments-archive/Alex/OlympicSports/DataSplit/';
zeroshot_datasplit_path = [datasplit_path,'Zeroshot/'];
labelvector_path = '/import/geb-experiments-archive/Alex/OlympicSports/Embedding/Word2Vec/';


DETECTOR = 'ITF'; % DETECTOR type: STIP, DenseTrj
norm_flag = 1;   % normalization strategy: org,histnorm,zscore

%%% Determine which feature is included
ind = 1;
rest = FEATURETYPE;
while true
    [FeatureTypeList{ind},rest] = strtok(rest,'|');
    if isempty(rest)
        break;
    end
    ind = ind+1;
end


zeroshot_base_path = '/import/geb-experiments-archive/Alex/UCF101/ITF/FV/Zeroshot/jointcodebook/Embedding/';
regression_path = sprintf('%s',zeroshot_base_path);
model_path = sprintf([regression_path,'DatasetSplit_tr-%.1f_ts-%.1f/%s/MTLRegression/RMTL/'],perc_TrainingSet,perc_TestingSet,FEATURETYPE);
if ~exist(model_path,'dir')
    mkdir(model_path);
end

%% Load Label Word Vector Representation
temp = load(sprintf([labelvector_path,'ClassLabelPhraseDict_mth-%s.mat'],EmbeddingMethod));
Para.phrasevec_mat = temp.phrasevec_mat;

%% Load Dataset Info
temp = load('/import/geb-experiments-archive/Alex/OlympicSports/DataSplit/Multishot/DataSplit.mat');
Para.ClassNoPerVideo = temp.DataSplit.ClassNoPerVideo;

%% Precompute Distance Matrix
Kernel = 'linear';   % name for kernel we used

if isempty(D)
    
    kernel_path = '/import/geb-experiments-archive/Alex/RegressionTransfer/MergeData/Kernel/';
    kernel_filepath = sprintf([kernel_path,'AugmentedDistMatrix_t-%s_s-%.0g_c-%d_p-%s_n-%d_descr-%s_alpha-%.2f.mat'],...
        cluster_type,nSample,CodebookSize,process,norm_flag,FEATURETYPE,alpha);
    
    if exist(kernel_filepath,'file')
        
        %%% Load precompute Kernel
        load(kernel_filepath);
        
    else
        DataType = 'all';
        
        %% Load Auxiliary Dataset
        [FVFeature_HMDB51,tr_LabelVec_HMDB51]=func_CollectHMDB51(DataType);
        [FVFeature_UCF101,tr_LabelVec_UCF101]=func_CollectUCF101(DataType);
        [FVFeature_OlympicSports,tr_LabelVec_OlympicSports]=func_CollectOlympicSports(DataType);
        [FVFeature_CCV,tr_LabelVec_CCV]=func_CollectCCV(DataType);
        
        idx_HMDB51 = 1:size(FVFeature_HMDB51,1);
        idx_UCF101 = idx_HMDB51(end)+1:idx_HMDB51(end)+size(FVFeature_UCF101,1);
        idx_OlympicSports = idx_UCF101(end)+1:idx_UCF101(end)+size(FVFeature_OlympicSports,1);
        idx_CCV = idx_OlympicSports(end)+1:idx_OlympicSports(end)+size(FVFeature_CCV,1);
        
        all_FeatureMat = [FVFeature_HMDB51 ; FVFeature_UCF101 ; FVFeature_OlympicSports ; FVFeature_CCV];
        
        D = func_PrecomputeKernel(all_FeatureMat,all_FeatureMat,'linear');
        
        save(kernel_filepath,'D','idx_HMDB51','idx_UCF101','idx_OlympicSports','idx_CCV',...
            'tr_LabelVec_HMDB51','tr_LabelVec_UCF101','tr_LabelVec_OlympicSports','tr_LabelVec_CCV','-v7.3');
        
    end
end


model_path = '/import/geb-experiments-archive/Alex/MTL/OlympicSports/L2Classification/Model/';
if ~exist(model_path,'dir')
    mkdir(model_path);
end

perf_path = '/import/geb-experiments-archive/Alex/MTL/OlympicSports/L2Classification/Perf/';
if ~exist(perf_path,'dir')
    mkdir(perf_path);
end

% ESZSLPerf = {};
Para.lambda = 1e-3;
Para.gamma = 1e-3;

%% Grid Search para
% for lambda = lambda_range
%     for gamma = gamma_range
%
%         Para.lambda = lambda;
%         Para.gamma = gamma;

for trial = 1:50
    
    %%% Check if model is computed
    model_filepath = sprintf([model_path,'L2Classification_trial-%d_embed-%s_lambda-%g_gamma-%g_task-dim_aug-1_ExOverlap.mat'],trial,EmbeddingMethod,Para.lambda,Para.gamma);
    if ~exist(model_filepath,'file')
        fprintf('Doesn'' Exist %s\n',model_filepath);
        continue;
    else
        fprintf('Exist %s\n',model_filepath);
        try load(model_filepath,'Model');
        catch
            fprintf('Corrupted %s\n',model_filepath);
            continue;
        end
    end
    
    %%% Zeroshot Datasplit
    load(sprintf([zeroshot_datasplit_path,'DatasetSplit_tr-%.1f_ts-%.1f_t-%d.mat'],perc_TrainingSet,perc_TestingSet,trial));
    
    Para.idx_TrainingSet = sort(idx_TrainingSet,'ascend');
    Para.idx_TestingSet = sort(idx_TestingSet,'ascend');
    clear idx_TrainingSet idx_TestingSet;
    
    %% Prepare Training Data
    tr_sample_ind = zeros(size(Para.ClassNoPerVideo,1),1);   % train sample index
    for c_tr = 1:length(Para.idx_TrainingSet)
        
        %% Extract Training Features for each class
        class_no = Para.idx_TrainingSet(c_tr);
        tr_sample_class_ind = Para.ClassNoPerVideo == class_no;
        tr_sample_ind = tr_sample_ind + tr_sample_class_ind;
    end
    
    Para.tr_sample_ind = logical(tr_sample_ind);
    Para.ts_sample_ind = ~tr_sample_ind;
    clear tr_sample_ind ts_sample_ind;
    
    %% Load Nonoverlap Index
    nonoverlap_path = '/import/geb-experiments-archive/Alex/ResolveOverlapCategory/';
    load(fullfile(nonoverlap_path,'OlympicSports_Overlap.mat'),'exl_idx_HMDB51','exl_idx_UCF101','exl_idx_CCV');
    
     %% Generate Testing Kernel Matrix
    selected_tr_idx = Para.tr_sample_ind'.*idx_OlympicSports;
    selected_tr_idx = selected_tr_idx(selected_tr_idx~=0);
%         aug_tr_idx = [idx_HMDB51(exl_idx_HMDB51) idx_UCF101(exl_idx_UCF101)  selected_tr_idx idx_CCV(exl_idx_CCV)];

    Para.selected_tr_idx = [idx_HMDB51(exl_idx_HMDB51) idx_UCF101(exl_idx_UCF101)  selected_tr_idx idx_CCV(exl_idx_CCV)];
    selected_ts_idx = Para.ts_sample_ind'.*idx_OlympicSports;
    Para.selected_ts_idx = selected_ts_idx(selected_ts_idx~=0);
    
    %         V_te = func_L2Normalization(Para.phrasevec_mat( Para.idx_TestingSet,:))';
%     Z = zscore(func_L2Normalization(Para.phrasevec_mat));
        Z = (func_L2Normalization(Para.phrasevec_mat));

    V_te = Z( Para.idx_TestingSet,:)';
    
    K_te = D(Para.selected_tr_idx,Para.selected_ts_idx);
    Y_GT = Para.ClassNoPerVideo(Para.ts_sample_ind);
    
    
    [map,ap] = func_ts_ZSL_KernelizedL2Classification_MAP(K_te,V_te,Y_GT,Para,Model);
    
    TrialMap(trial) = map;
    
%     ESZSLPerf = [ESZSLPerf;{Para.lambda Para.gamma meanAcc}];
end
% end
mean(TrialMap)
std(TrialMap)