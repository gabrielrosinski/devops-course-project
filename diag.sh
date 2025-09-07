#!/bin/bash
# Diagnostic script for Earthquake Deployment

echo "🔹 Applying Deployment and ConfigMap..."
kubectl apply -f deploy.yaml

echo "⏳ Waiting for Pod to be in Running state..."
POD=""
# Wait until at least one pod is running (max 60s)
for i in {1..30}; do
    POD=$(kubectl get pods -l app=earthquake -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    STATUS=$(kubectl get pod $POD -o jsonpath='{.status.phase}' 2>/dev/null)
    if [[ "$STATUS" == "Running" ]]; then
        echo "✅ Pod $POD is Running!"
        break
    else
        echo "⏳ Pod is $STATUS, waiting..."
        sleep 2
    fi
done

if [[ "$STATUS" != "Running" ]]; then
    echo "❌ Pod did not reach Running state. Exiting."
    exit 1
fi

echo "🔹 Checking Deployment status..."
kubectl get deployments earthquake -o wide

echo "🔹 Checking ReplicaSet..."
kubectl get rs -l app=earthquake

echo "🔹 Listing Pods..."
kubectl get pods -l app=earthquake -o wide

POD=$(kubectl get pods -l app=earthquake -o jsonpath='{.items[0].metadata.name}')
echo "🔹 Inspecting Pod: $POD"
kubectl describe pod $POD

echo "🔹 Checking container logs..."
kubectl logs $POD

echo "🔹 Verifying ConfigMap mount..."
kubectl exec -it $POD -- ls /data
kubectl exec -it $POD -- cat /data/earthquake.conf

echo "🔹 Testing application endpoint (port-forward to 8080)..."
kubectl port-forward $POD 8080:5000 &
PF_PID=$!
sleep 2
curl http://localhost:8080 || echo "⚠️ Service not responding on port 80"
kill $PF_PID 2>/dev/null

echo "✅ Diagnostic completed!"
