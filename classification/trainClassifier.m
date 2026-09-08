function net = trainClassifier()
%TRAINCLASSIFIER  Train the DR grading CNN (transfer learning).
%
%   net = trainClassifier()
%
%   TODO(Sprint 2+): fine-tune the benchmark-selected backbone (ResNet-50 vs
%   EfficientNet-B0, docs/ARCHITECTURE.md §3.2 / §2 Stage 6) on APTOS 2019.
%   Refuse to run without data/model artifacts rather than pretending.
%
%   Sprint 0: this function never returns a trained model; it errors clearly.

    raiseError('trainClassifier', 'NotImplemented', ...
        'Training is a Sprint 2+ task (requires APTOS data + Deep Learning Toolbox).');
end