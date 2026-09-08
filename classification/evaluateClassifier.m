function evalOut = evaluateClassifier(net, testData)
%EVALUATECLASSIFIER  Honest hold-out evaluation of the DR classifier.
%
%   evalOut = evaluateClassifier(net, testData)
%
%   Outputs confusion matrix, ROC/AUC, referable SE/SP, kappa (primary target:
%   referable SE >90% / SP >85% on test + Messidor-2 external only).
%
%   TODO(Sprint 2+/8): implemented with evaluation/metrics.m. No fabricated
%   numbers — this function only reports what comes out of real evaluation.
%
%   Sprint 0: refuses to fabricate metrics.

    raiseError('evaluateClassifier', 'NotImplemented', ...
        'Evaluation is a Sprint 2+ task. No metrics are fabricated before then.');
end