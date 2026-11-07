// =====================================================================
// Portfolio 4 - Step 7, own work: a partial index for FRAUD_FLAG events.
//   mongosh $env:MONGODB_URI --file portfolio-4-nosql/05_own_partial_index.js |
//     Tee-Object -FilePath portfolio-4-nosql/output/05_own_partial_index.txt
//
// A partial index contains ONLY the documents that match its filter, so it
// is smaller and cheaper to maintain than a full index. Requires step 6
// (idx_audit_type_ts must exist). Re-runnable.
// =====================================================================

const nosql = db.getSiblingDB('quickfund_nosql');

function stageNames(plan) {
    const names = [];
    (function walk(node) {
        if (!node) return;
        if (node.stage) names.push(node.stage);
        if (node.inputStage) walk(node.inputStage);
        if (node.inputStages) node.inputStages.forEach(walk);
        if (node.queryPlan) walk(node.queryPlan);
    })(plan.queryPlanner.winningPlan);
    return names;
}
function report(label, cursor) {
    const ex = cursor.explain('executionStats');
    const s = ex.executionStats;
    print('  [' + label + ']');
    print('    plan stages        : ' + stageNames(ex).join(' > '));
    print('    documents examined : ' + s.totalDocsExamined);
    print('    index keys examined: ' + s.totalKeysExamined);
    print('    documents returned : ' + s.nReturned);
    print('    execution time (ms): ' + s.executionTimeMillis);
}

const since = new Date(Date.now() - 7 * 86400000);
const fraud = function () { return nosql.audit_events.find({ event_type: 'FRAUD_FLAG', ts: { $gte: since } }); };
const failed = function () { return nosql.audit_events.find({ event_type: 'LOGIN_FAILED', ts: { $gte: since } }); };

try { nosql.audit_events.dropIndex('idx_audit_fraud_partial'); } catch (e) { }
print(nosql.audit_events.createIndex(
    { ts: -1 },
    { name: 'idx_audit_fraud_partial', partialFilterExpression: { event_type: 'FRAUD_FLAG' } }));

print('\n############ FRAUD_FLAG query: full index vs partial index ############');
report('full index idx_audit_type_ts', fraud().hint('idx_audit_type_ts'));
report('partial index idx_audit_fraud_partial', fraud().hint('idx_audit_fraud_partial'));

print('\n############ LOGIN_FAILED query: the partial index cannot be used ############');
report('planner choice (no hint)', failed());

print('\n############ Index sizes (KB) ############');
try {
    const st = nosql.audit_events.aggregate([{ $collStats: { storageStats: {} } }]).toArray()[0].storageStats;
    Object.keys(st.indexSizes).forEach(function (k) {
        print('  ' + k + ': ' + (st.indexSizes[k] / 1024).toFixed(0) + ' KB');
    });
} catch (e) {
    print('  index sizes not available here (' + e.message + '). Use Atlas > Collections > Indexes tab instead.');
}
