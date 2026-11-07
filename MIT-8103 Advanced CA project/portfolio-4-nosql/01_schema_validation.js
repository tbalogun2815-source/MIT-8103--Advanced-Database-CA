// =====================================================================
// Portfolio 4 - Step 1: create the collections with schema validation.
//   mongosh $env:MONGODB_URI --file portfolio-4-nosql/01_schema_validation.js
//
// MongoDB is "schema-flexible", not "schema-less": we still enforce the
// fields that MUST exist, and leave the rest of each document free to vary.
// Safe to re-run: it drops and recreates the three collections.
// =====================================================================

const nosql = db.getSiblingDB('quickfund_nosql');

['kyc_profiles', 'audit_events', 'login_sessions'].forEach(function (name) {
    nosql.getCollection(name).drop();
});

// A UUID in text form, matching customers.customer_id in PostgreSQL.
const UUID_PATTERN = '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';

// ---------------------------------------------------------------------
// kyc_profiles: one document per customer. The `documents` array holds
// identity documents, and each document type has DIFFERENT fields
// (a passport has an expiry date, a BVN does not). That variety is the
// reason this data does not fit neatly into one SQL table.
// customer_id points at customers.customer_id in PostgreSQL.
// ---------------------------------------------------------------------
nosql.createCollection('kyc_profiles', {
    validator: {
        $jsonSchema: {
            bsonType: 'object',
            required: ['customer_id', 'tier', 'status', 'documents', 'created_at'],
            properties: {
                customer_id: {
                    bsonType: 'string', pattern: UUID_PATTERN,
                    description: 'must match customers.customer_id (UUID) in PostgreSQL'
                },
                tier: { bsonType: 'number', minimum: 1, maximum: 3 },
                status: { enum: ['PENDING', 'VERIFIED', 'REJECTED'] },
                documents: {
                    bsonType: 'array',
                    minItems: 1,
                    items: {
                        bsonType: 'object',
                        required: ['type', 'number'],
                        properties: {
                            type: { enum: ['BVN', 'NIN', 'PASSPORT', 'DRIVERS_LICENCE', 'UTILITY_BILL'] },
                            number: { bsonType: 'string' }
                        }
                    }
                },
                created_at: { bsonType: 'date' }
            }
        }
    },
    validationAction: 'error'
});

// ---------------------------------------------------------------------
// audit_events: an append-only log of what happened. Different event
// types carry different `details`, and new event types can be added
// without altering a table.
// ---------------------------------------------------------------------
nosql.createCollection('audit_events', {
    validator: {
        $jsonSchema: {
            bsonType: 'object',
            required: ['customer_id', 'event_type', 'ts', 'details'],
            properties: {
                customer_id: { bsonType: 'string', pattern: UUID_PATTERN },
                event_type: {
                    enum: ['LOGIN_SUCCESS', 'LOGIN_FAILED', 'PIN_CHANGED',
                        'TRANSFER_INITIATED', 'KYC_UPGRADED', 'FRAUD_FLAG']
                },
                ts: { bsonType: 'date' },
                details: { bsonType: 'object' }
            }
        }
    },
    validationAction: 'error'
});

// ---------------------------------------------------------------------
// login_sessions: short-lived data. A TTL index deletes each document
// automatically one hour after created_at. (Created in the index step.)
// ---------------------------------------------------------------------
nosql.createCollection('login_sessions');

print('Collections now in quickfund_nosql:');
nosql.getCollectionNames().forEach(function (n) { print('  - ' + n); });

// ---------------------------------------------------------------------
// Prove the validator works: this insert is missing required fields and
// has an invalid customer_id and status, so MongoDB must reject it.
// ---------------------------------------------------------------------
try {
    nosql.kyc_profiles.insertOne({ customer_id: 'not-a-uuid', status: 'MAYBE' });
    print('FAIL: the invalid document was accepted');
} catch (e) {
    print('PASS: invalid KYC document rejected -> ' + (e.code === 121 ? 'DocumentValidationFailure' : e.codeName) + ' (code ' + e.code + ')');
}