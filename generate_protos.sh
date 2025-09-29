# Generate Python gRPC stubs for all domains
# Requires: pip install grpcio-tools


ROOT_DIR=$(cd "$(dirname "$0")" && pwd)
PROTO_DIR="$ROOT_DIR/protos"


# map domain → service output dir
DOMAINS=(forex ledger payment profile rule-engine wallet)


for domain in "${DOMAINS[@]}"; do
SRC_DIR="$PROTO_DIR/$domain/v1"
[[ -d "$SRC_DIR" ]] || { echo "skip $domain (no protos)"; continue; }
case "$domain" in
rule-engine) SVC=rule-engine;;
*) SVC=$domain;;
esac
OUT_DIR="$ROOT_DIR/services/$SVC/app/generated"
mkdir -p "$OUT_DIR"
python -m grpc_tools.protoc \
-I "$PROTO_DIR" \
--python_out="${OUT_DIR}" \
--grpc_python_out="${OUT_DIR}" \
"$SRC_DIR"/*.proto
echo "generated → $OUT_DIR"
done