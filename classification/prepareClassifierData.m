function data = prepareClassifierData(manifest)
%PREPARECLASSIFIERDATA  Build input tensors for classifier training/inference.
%
%   data = prepareClassifierData(manifest)
%
%   manifest: data table/CSV (columns image, eye_id, grade, split, source).
%
%   TODO(Sprint 2+): load config/data/raw, resample to inputSize, apply fixed-seed
%   augmentation (flip/rotate/scale/color-jitter), class weights/focal loss for
%   imbalance (docs/ARCHITECTURE.md §8).
%
%   Sprint 0: returns an empty placeholder; NOT callable with real data yet.

    raiseError('prepareClassifierData', 'NotImplemented', ...
        'Prepare-classifier-data is a Sprint 2+ task (training path).');
end