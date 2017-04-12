%% script to run 50 indepedent datasplits for ZSL
clear;
global D idx_HMDB51 idx_UCF101 idx_OlympicSports idx_CCV tr_LabelVec_HMDB51 tr_LabelVec_UCF101 tr_LabelVec_OlympicSports tr_LabelVec_CCV;

addpath('/import/geb-experiments/Alex/ICCV15/code/SharedTools/function/');
addpath('/import/geb-experiments/Alex/Matlab/Techniques/poblano_toolbox');
addpath('/import/geb-experiments/Alex/ECCV16/code/MTL/SharedTools/VideoStory/function');


%
Para.perc_TrainingSet = 0.5;
Para.perc_TestingSet = 1 - Para.perc_TrainingSet;
Para.cluster_type = 'vlfeat';
Para.nSample = 256000;
Para.CodebookSize = 128;
Para.process = 'org'; % preprocess of dataset: org,sta
Para.FEATURETYPE = 'HOF|HOG|MBH';
Para.nPCA = 0;
SelfTraining = 0;   % Indicator if do selftraining
trial = 1;
Para.EmbeddingMethod = 'add';

Para.lambdaD_range = [1e-3 1e-4 1e-5];
Para.lambdaA_range = [1e-3 1e-4 1e-5];
Para.lambdaS_range = [1e-3 1e-4 1e-5];

Para.lambdaD_range = [1e-3 1e-4 1e-5];
Para.lambdaA_range = [1e-5];
Para.lambdaS_range = [1e-3 1e-4 1e-5];
Para.LatentDim_range = [50 60 70 80];

% Para.lambdaD_range = [1e-4 1e-5];
% Para.lambdaA_range = [1e-4 1e-5];
% Para.lambdaS_range = [1e-4 1e-5];
% Para.LatentDim_range = 60;

alpha = 0.2;
SelfTraining = 0;

%% Internal Parameters
multishot_base_path = '/import/vision-datasets2/HMDB51/hmdb51_multishot/';
feature_data_base_path = '/import/geb-experiments-archive/Alex/HMDB51/ITF/FV/jointcodebook/';
zeroshot_base_path = '/import/geb-experiments-archive/Alex/HMDB51/ITF/FV/Zeroshot/jointcodebook/Embedding/';

DETECTOR = 'ITF'; % DETECTOR type: STIP, DenseTrj
norm_flag = 1;   % normalization strategy: org,histnorm,zscore

%%% Determine which feature is included
ind = 1;
rest = Para.FEATURETYPE;
while true
    [FeatureTypeList{ind},rest] = strtok(rest,'|');
    if isempty(rest)
        break;
    end
    ind = ind+1;
end


zeroshot_base_path = '/import/geb-experiments-archive/Alex/UCF101/ITF/FV/Zeroshot/jointcodebook/Embedding/';
regression_path = sprintf('%s',zeroshot_base_path);
model_path = sprintf([regression_path,'DatasetSplit_tr-%.1f_ts-%.1f/%s/MTLRegression/RMTL/'],Para.perc_TrainingSet,Para.perc_TestingSet,Para.FEATURETYPE);
if ~exist(model_path,'dir')
    mkdir(model_path);
end

%% Load Label Word Vector Representation
wordvec_path = '/import/vision-datasets2/HMDB51/hmdb51_wordvec/';
temp = load(sprintf([wordvec_path,'ClassLabelPhraseDict_mth-%s.mat'],Para.EmbeddingMethod));
Para.phrasevec_mat = temp.phrasevec_mat;
Para.ClassLabelsPhrase = temp.ClassLabelsPhrase;

%% Load Dataset Info
temp = load([multishot_base_path,'DataSplit.mat']);
Para.sample_class_ind = temp.data_split{1};
Para.ClassNoPerVideo = temp.ClassNoPerVideo;

%% Precompute Distance Matrix
Kernel = 'linear';   % name for kernel we used

if isempty(D)
    
    kernel_path = '/import/geb-experiments-archive/Alex/RegressionTransfer/MergeData/Kernel/';
    kernel_filepath = sprintf([kernel_path,'AugmentedDistMatrix_t-%s_s-%.0g_c-%d_p-%s_n-%d_descr-%s_alpha-%.2f.mat'],...
        Para.cluster_type,Para.nSample,Para.CodebookSize,Para.process,norm_flag,Para.FEATURETYPE,alpha);
    
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


%% Run 50 random splits


term_path = '/import/geb-experiments-archive/Alex/Joint/HMDB51/VideoStory/Precompute/';
if ~exist(term_path,'dir')
    mkdir(term_path);
end

perf_path = '/import/geb-experiments-archive/Alex/Joint/HMDB51/VideoStory/KLIEPY/Perf/';
if ~exist(perf_path,'dir')
    mkdir(perf_path);
end

%%% Importance Weighting
% weight_model_path = '/import/geb-experiments-archive/Alex/ImportanceWeighting/HMDB51/KLIEP_Y/Model/';
weight_model_path = '/import/geb-experiments-archive/Alex/ImportanceWeighting/HMDB51/KLIEP_Y/Model/';

% Para.sigmaX = 0.15;
Para.sigmaY = 0.2;

% Para.sigmaX = 0.15;
% Para.sigmaY = 0.3;

for trial = 1:5
    for lambdaA = Para.lambdaA_range
        
        %%% Check if precomputed term is computed
        term_filepath = sprintf([term_path,...
            'term_pinvKKt_trial-%d_lambdaA-%g_aug-1.mat'],...
            trial,lambdaA);
        if ~exist(term_filepath,'file')
            fid = fopen(term_filepath,'w');
            fclose(fid);
            fprintf('Start %s\n',term_filepath);
            
        else
            fprintf('Exist %s\n',term_filepath);
            %                         continue;
        end
        
        
        %% Load Data Split
        datasplit_path = sprintf('/import/vision-datasets2/HMDB51/hmdb51_%s_ZeroRegression/DatasetSplit/',Para.process);
        load(sprintf([datasplit_path,'DatasetSplit_tr-%.1f_ts-%.1f_t-%d.mat'],Para.perc_TrainingSet,Para.perc_TestingSet,trial));
        Para.idx_TrainingSet = sort(idx_TrainingSet,'ascend');
        Para.idx_TestingSet = sort(idx_TestingSet,'ascend');
        clear idx_TrainingSet idx_TestingSet;
        
         %% Load weight
                    XYmodel_filepath = sprintf([weight_model_path,'LinearRegress_trial-%d_embed-%s_sigma-%g_aug-1_norm-zscore_ccv.mat'],trial,Para.EmbeddingMethod,Para.sigmaY);
                    KLIEP_Y = load(XYmodel_filepath,'Model');
                    weight = KLIEP_Y.Model.weight;
                    
        %% Prepare Training Data
        tr_sample_ind = zeros(size(Para.sample_class_ind,1),1);   % train sample index
        
        for c_tr = 1:length(Para.idx_TrainingSet)
            
            %% Extract Training Features for each class
            currentClassName = Para.ClassLabelsPhrase{Para.idx_TrainingSet(c_tr)};
            tr_sample_class_ind = ismember(Para.sample_class_ind(:,1),currentClassName);
            tr_sample_ind = tr_sample_ind + tr_sample_class_ind;
        end
        
        Para.tr_sample_ind = logical(tr_sample_ind);
        Para.ts_sample_ind = ~tr_sample_ind;
        clear tr_sample_ind ts_sample_ind;
        
        
        %% Generate Training Kernel Matrix
        selected_tr_idx = Para.tr_sample_ind'.*idx_HMDB51;
        selected_tr_idx = selected_tr_idx(selected_tr_idx~=0);
        aug_tr_idx = [ selected_tr_idx idx_UCF101 idx_OlympicSports idx_CCV];
        N_l = numel(aug_tr_idx);
        
%         Z_All = zscore(func_L2Normalization([tr_LabelVec_HMDB51 ; tr_LabelVec_UCF101 ; tr_LabelVec_OlympicSports ; tr_LabelVec_CCV]));
%         Z = Z_All(aug_tr_idx,:)'*sparse(1:N_l,1:N_l,sqrt(weight));
        
        
        K = D(aug_tr_idx,aug_tr_idx)*sparse(1:N_l,1:N_l,sqrt(weight));
        
        N_K = size(K,1);
        tic;
        Term_pinvKKt = K'/(K*K' + lambdaA*N_K*eye(N_K));
        toc;
        
        %% Train VS Model
        %                     param.MaxItr = 30;
        %                     param.epsilon = 5e-3;
        %                     [Model.D, Model.A , Model.S , Model.L]=func_KernelizedVideoStory(K,Z,LatentDim,lambdaD,lambdaS,lambdaA,param);
        
        %%% Save Result
        save(term_filepath,'Term_pinvKKt','-v7.3');
    end
end
%         end
%     end
% end