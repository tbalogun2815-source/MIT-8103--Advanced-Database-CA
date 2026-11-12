// =====================================================================
// Portfolio 5, own work: what does w:majority cost compared with w:1?
// Run against your Atlas cluster (3-node replica set).
//   mongosh $env:MONGODB_URI --file portfolio-5-distributed-cloud/05_own_write_concern.js |
//     Tee-Object -FilePath portfolio-5-distributed-cloud/output/05_own_write_concern.txt
// =====================================================================
const coll = db.getSiblingDB('quickfund_nosql').getCollection('p5_wc_test');
coll.drop();

function run(label, wc, n) {
    const t0 = Date.now();
    for (let i = 0; i < n; i++) {
        coll.insertOne({ i: i, label: label, at: new Date() }, { writeConcern: wc });
    }
    const ms = Date.now() - t0;
    print(label + ': ' + n + ' inserts in ' + ms + ' ms (' + (ms / n).toFixed(1) + ' ms each)');
}

print('=== Write concern cost, 100 sequential inserts each');
run('w:1 (primary only)', { w: 1 }, 100);
run('w:majority (2 of 3 nodes)', { w: 'majority', wtimeout: 5000 }, 100);
run('w:1 again (to check for noise)', { w: 1 }, 100);

coll.drop();
print('Cleaned up.');