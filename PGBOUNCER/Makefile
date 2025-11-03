BASE_NAMES = POSTGRES LANGFLOW
DOCKERHUB_BASE_NAMES = PGBOUNCER
SERVICES = POSTGRES LANGFLOW PGBOUNCER
DEPLOYS = POSTGRES PGBOUNCER LANGFLOW
PORTFORWARD = POSTGRES LANGFLOW PGBOUNCER
PODS = postgres langflow
DEFAULT_WORKERS ?= 1
BENCHMARK_TYPE ?= hey

# ---------------------------------------------------------------------------------
# ---------------------------- get base imaged from aws ---------------------------
# ---------------------------------------------------------------------------------
aws-login: apply-config
	@echo "======================= CONFIGURING AWS CLI =========================="
	@AWS_ACCESS_KEY_ID=$$(kubectl get secret global-secret -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' | base64 --decode); \
	AWS_SECRET_ACCESS_KEY=$$(kubectl get secret global-secret -o jsonpath='{.data.AWS_SECRET_ACCESS_KEY}' | base64 --decode); \
	AWS_DEFAULT_REGION=$$(kubectl get configmap global-config -o jsonpath='{.data.AWS_DEFAULT_REGION}'); \
	aws configure set aws_access_key_id "$${AWS_ACCESS_KEY_ID}"; \
	aws configure set aws_secret_access_key "$${AWS_SECRET_ACCESS_KEY}"; \
	aws configure set region "$${AWS_DEFAULT_REGION}";
	@echo "======================= LOGGING IN TO AWS ECR =========================="
	@AWS_ECR_REGISTRY_URL=$$(kubectl get configmap global-config -o jsonpath='{.data.AWS_ECR_REGISTRY_URL}'); \
	aws ecr get-login-password --region $$(kubectl get configmap global-config -o jsonpath='{.data.AWS_DEFAULT_REGION}') | \
	docker login --username AWS --password-stdin "$${AWS_ECR_REGISTRY_URL}"

base-build:
	@echo "----------------- Starting port-forward to local registry -------------------"
	@kubectl port-forward svc/registry 5000:5000 &
	@echo "Waiting for port-forward..." && sleep 5

	@echo "----------------- Pulling, Tagging, and Pushing Base Images -------------------"
	@AWS_ECR_REGISTRY_URL=$$(kubectl get configmap global-config -o jsonpath='{.data.AWS_ECR_REGISTRY_URL}'); \
	IMG_PREFIX=$$(kubectl get configmap global-config -o jsonpath='{.data.IMG_PREFIX}'); \
	ENV_TAG=$$(kubectl get configmap global-config -o jsonpath='{.data.ENV_TAG}'); \
	BITBUCKET_BRANCH=$$(kubectl get configmap global-config -o jsonpath='{.data.BITBUCKET_BRANCH}'); \
	for base_name in $(BASE_NAMES); do \
    		config_map=$$(echo $$base_name | tr 'A-Z' 'a-z')-config; \
    		\
    		IMAGE_NAME=$$(kubectl get configmap $$config_map -o jsonpath="{.data.$${base_name}_IMAGE}"); \
    		VERSION=$$(kubectl get configmap $$config_map -o jsonpath="{.data.$${base_name}_VERSION}"); \
    		LOCAL_TAG=$$(kubectl get configmap $$config_map -o jsonpath="{.data.$${base_name}_BUILT_IMAGE}"); \
    		\
    		ECR_IMAGE_PATH="$${AWS_ECR_REGISTRY_URL}/$${IMG_PREFIX}-$${IMAGE_NAME}:$${ENV_TAG}-$${BITBUCKET_BRANCH}-$${VERSION}"; \
    		LOCAL_IMAGE_PATH="localhost:5000/$${LOCAL_TAG}"; \
    		\
    		echo "--- Processing service: $$base_name ---"; \
    		echo "Pulling from: $${ECR_IMAGE_PATH}"; \
    		docker pull "$${ECR_IMAGE_PATH}"; \
    		echo "Tagging as: $${LOCAL_IMAGE_PATH}"; \
    		docker tag "$${ECR_IMAGE_PATH}" "$${LOCAL_IMAGE_PATH}"; \
    		docker push "$${LOCAL_IMAGE_PATH}"; \
    		echo "--- Done ---"; \
    	done

	@echo "----------------- Pulling, Tagging, and Pushing Docker Hub Base Images -------------------"
	@for base_name in $(DOCKERHUB_BASE_NAMES); do \
			config_map=$$(echo $$base_name | tr 'A-Z' 'a-z')-config; \
			\
			DOCKERHUB_IMAGE_PATH=$$(kubectl get configmap $$config_map -o jsonpath="{.data.$${base_name}_IMAGE}"); \
			LOCAL_TAG=$$(kubectl get configmap $$config_map -o jsonpath="{.data.$${base_name}_BUILT_IMAGE}"); \
			LOCAL_IMAGE_PATH="localhost:5000/$${LOCAL_TAG}"; \
			\
			echo "--- Processing Docker Hub service: $$base_name ---"; \
			echo "Pulling from: $${DOCKERHUB_IMAGE_PATH}"; \
			docker pull "$${DOCKERHUB_IMAGE_PATH}"; \
			echo "Tagging as: $${LOCAL_IMAGE_PATH}"; \
			docker tag "$${DOCKERHUB_IMAGE_PATH}" "$${LOCAL_IMAGE_PATH}"; \
			docker push "$${LOCAL_IMAGE_PATH}"; \
			echo "--- Done ---"; \
		done

	@echo "----------------- Verifying images in local registry -------------------"
	@curl -s http://localhost:5000/v2/_catalog
	@echo "----------------- Killing port-forward process -------------------"
	@pkill -f "kubectl port-forward.*5000" || true

# ---------------------------------------------------------------------------------
# ------------------------------ Minikube Management ------------------------------
# ---------------------------------------------------------------------------------
mk-up: mk-config
	@echo "----------------- Starting Minikube -------------------"
	minikube start --insecure-registry="192.168.0.0/16" --force

mk-stop:
	@echo "----------------- Stopping Minikube -------------------"
	-minikube stop

mk-delete:
	@echo "----------------- Deleting Minikube cluster -------------------"
	-minikube delete

mk-restart: mk-stop mk-up
	@echo "----------------- Restarting Minikube -------------------"

mk-setup:
	@echo "----------------- Mounting working directory into Minikube -------------------"
	docker cp . minikube:/workspace

# ---------------------------------------------------------------------------------
# -------------------------------- build Minikube ---------------------------------
# ---------------------------------------------------------------------------------

mk-build: mk-stop mk-delete mk-up mk-setup pre-build apply-config apply-instances-config aws-login base-build

pre-build:
	@echo "----------------- Auto-configuring resource limits -------------------"
	@CPU_CORES=$$(nproc); \
	TOTAL_MEM_GB=$$(free -g | awk '/^Mem:/ {print $$2}'); \
	\
	export LIMIT_CPU=$$(($$CPU_CORES - 2)); \
	export LIMIT_MEM=$$(($$TOTAL_MEM_GB - 4))Gi; \
	\
	export REQUEST_CPU=1; \
	export REQUEST_MEM=4Gi; \
	\
	echo "Detected $$CPU_CORES CPU cores and $$TOTAL_MEM_GB GB RAM."; \
	echo "Setting default container limits to: $$LIMIT_CPU cores and $$LIMIT_MEM memory."; \
	echo "Setting default container requests to: $$REQUEST_CPU core and $$REQUEST_MEM memory."; \
	\
	envsubst < kubernetes/limits.yaml.tpl > kubernetes/limits.yaml;
	@echo "kubernetes/limits.yaml generated successfully."
# ---------------------------------------------------------------------------------
# --------------------------------- apply configs ---------------------------------
# ---------------------------------------------------------------------------------
mk-config:
	@echo "----------------- Dynamically Configuring Minikube VM based on HOST resources -------------------"
	@CPU_CORES=$$(nproc); \
	TOTAL_MEM_MB=$$(free -m | awk '/^Mem:/ {print $$2}'); \
	\
	MINIKUBE_CPUS=$$(( $$CPU_CORES > 4 ? $$CPU_CORES - 2 : $$CPU_CORES )); \
	MINIKUBE_MEM_MB=$$(( $$TOTAL_MEM_MB > 8192 ? $$TOTAL_MEM_MB - 4096 : $$TOTAL_MEM_MB )); \
	\
	echo "Host has $$CPU_CORES CPUs and $$TOTAL_MEM_MB MB RAM."; \
	echo "--> Configuring Minikube with $$MINIKUBE_CPUS CPUs and $$MINIKUBE_MEM_MB MB RAM."; \
	\
	minikube config unset insecure-registry || true; \
	minikube config set insecure-registry "registry.default.svc.cluster.local:5000"; \
	minikube config set insecure-registry "localhost:5000"; \
	minikube config set memory "$${MINIKUBE_MEM_MB}"; \
	minikube config set cpus "$${MINIKUBE_CPUS}";
apply-config:
	@echo "----------------- Applying Kubernetes Registry -------------------"
	kubectl apply -f kubernetes/registry.yaml
	kubectl rollout status deployment registry -n default --timeout=180s
	@echo "----------------- Ensuring registry is ready -------------------"
	@echo "Waiting for registry pod to be ready..."
	@kubectl wait --for=condition=ready pod -l app=registry -n default --timeout=90s
	@echo "Registry pod is ready!"
	@sleep 2
	@echo "----------------- Applying Kubernetes Namespace Limits -------------------"
	kubectl apply -f kubernetes/limits.yaml
	@echo "----------------- Applying Global Configs & Secrets -------------------"
	kubectl apply -f kubernetes/global-config.yaml
	kubectl apply -f kubernetes/global-secret.yaml

apply-instances-config:
	@echo "----------------- Applying Postgres Persistent Volume Claim -------------------"
	kubectl apply -f kubernetes/postgres/postgres-pvc.yaml
	@echo "----------------- Applying Postgres ConfigMaps and Secrets -------------------"
	kubectl apply -f kubernetes/postgres/postgres-init-cm.yaml
	kubectl apply -f kubernetes/postgres/postgres-config.yaml
	kubectl apply -f kubernetes/postgres/postgres-secret.yaml
	@echo "----------------- Applying Langflow Persistent Volume Claim -------------------"
	kubectl apply -f kubernetes/langflow/langflow-pvc.yaml
	@echo "----------------- Applying Langflow ConfigMaps and Secrets -------------------"
	kubectl apply -f kubernetes/langflow/langflow-config.yaml
	kubectl apply -f kubernetes/langflow/langflow-secret.yaml
	@echo "----------------- Applying PgBouncer ConfigMaps -------------------"
	kubectl apply -f kubernetes/pgbouncer/pgbouncer-config.yaml

# ---------------------------------------------------------------------------------
# ----------------------------------- BUILD k8s -----------------------------------
# ---------------------------------------------------------------------------------

build-k8s: mk-setup build-k8s-postgres build-k8s-langflow build-k8s-pgbouncer

build-k8s-postgres:
	@echo "----------------- Building Postgres for Kubernetes -------------------"
	@kubectl delete job postgres-build --ignore-not-found=true
	@kubectl apply -f kubernetes/postgres/postgres-build-job.yaml
	@echo "Waiting for Postgres build job to complete..."
	@kubectl wait --for=condition=complete job/postgres-build --timeout=90s || \
		(echo "!!! Postgres build failed, showing logs: !!!" && kubectl logs job/postgres-build --follow && exit 1)
	@echo "Postgres build completed successfully."
build-k8s-langflow:
	@echo "----------------- Building Langflow for Kubernetes -------------------"
	@kubectl delete job langflow-build --ignore-not-found=true
	@kubectl apply -f kubernetes/langflow/langflow-build-job.yaml
	@echo "Waiting for Langflow build job to complete..."
	@kubectl wait --for=condition=complete job/langflow-build --timeout=120s || \
		(echo "!!! Langflow build failed, showing logs: !!!" && kubectl logs job/langflow-build --follow && exit 1)
	@echo "Langflow build completed successfully."
build-k8s-pgbouncer:
	@echo "----------------- Building PgBouncer for Kubernetes -------------------"
	@kubectl delete job pgbouncer-build --ignore-not-found=true
	@kubectl apply -f kubernetes/pgbouncer/pgbouncer-build-job.yaml
	@echo "Waiting for PgBouncer build job to complete..."
	@kubectl wait --for=condition=complete job/pgbouncer-build --timeout=90s || \
		(echo "!!! PgBouncer build failed, showing logs: !!!" && kubectl logs job/pgbouncer-build --follow && exit 1)
	@echo "PgBouncer build completed successfully."
build-benchmark-image:
	@echo "----------------- Starting port-forward to local registry for benchmark image -------------------"
	@kubectl port-forward svc/registry 5000:5000 & export BG_PID=$$!; \
	echo "Waiting for port-forward (PID: $$BG_PID)..." && sleep 5; \
	echo "----------------- Building and Pushing Benchmark Image -------------------"; \
	docker build --no-cache -t localhost:5000/benchmark:latest -f kubernetes/benchmark/docker/Dockerfile kubernetes/benchmark; \
	docker push localhost:5000/benchmark:latest; \
	echo "----------------- Killing port-forward process (PID: $$BG_PID) -------------------"; \
	kill $$BG_PID;

# ---------------------------------------------------------------------------------
# ----------------------------------- MANAGE k8s ----------------------------------
# ---------------------------------------------------------------------------------

init-k8s: up-k8s init-langflow-users create-test-flow
	@echo "----------------- Kubernetes initialized. -------------------"

up-k8s: down-k8s delete-pods create-services deploy-k8s port-forward-services
	@echo "----------------- System is up. Listing running Kubernetes pods -------------------"
	kubectl get pods
	@echo "----------------- Checking Worker Status -------------------"
	@$(MAKE) check-workers

delete-pods:
	@for pod in $(PODS); do \
		echo "----------------- Deleting $$pod_app pods... -------------------"; \
		kubectl delete pods -l app=$$pod --ignore-not-found=true; \
	done
	@-kubectl delete pods -l job-name=langflow-benchmark --force --grace-period=0

create-services:
	@for service in $(SERVICES); do \
		echo "----------------- Creating $$service Service -------------------"; \
		service_lower=$$(echo $$service | tr 'A-Z' 'a-z'); \
		config_map=$${service_lower}-config; \
        \
        SERVICE=$$(kubectl get configmap $$config_map -o jsonpath="{.data.$${service}_SERVICE}"); \
        PORT=$$(kubectl get configmap $$config_map -o jsonpath="{.data.$${service}_PORT}"); \
        export SERVICE PORT; \
        envsubst < kubernetes/$${service_lower}/$${service_lower}-service.yaml | kubectl apply -f -; \
	done

deploy-k8s:
	@for deploy in $(DEPLOYS); do \
		echo "----------------- Deploying $$deploy to Kubernetes -------------------"; \
		deploy_lower=$$(echo $$deploy | tr 'A-Z' 'a-z'); \
		config_map="$${deploy_lower}-config"; \
		\
		REGISTRY_HOST=$$(minikube ip); \
		BUILT_IMAGE=$$(kubectl get configmap $$config_map -o jsonpath="{.data.$${deploy}_BUILT_IMAGE}"); \
		PORT=$$(kubectl get configmap $$config_map -o jsonpath="{.data.$${deploy}_PORT}"); \
		export REGISTRY_HOST BUILT_IMAGE PORT; \
		\
		envsubst < kubernetes/$$deploy_lower/$$deploy_lower-deployment.yaml | kubectl apply -f -; \
		\
		echo "----------------- Waiting for $$deploy_lower pod to be ready -------------------"; \
		kubectl wait --for=condition=ready pod -l app=$$deploy_lower --timeout=180s; \
		\
		echo "----------------- Testing $$deploy_lower Service -------------------"; \
		SERVICE_NAME=$$(kubectl get configmap $$config_map -o jsonpath="{.data.$${deploy}_SERVICE}"); \
		kubectl get service $$SERVICE_NAME; \
	done

down-k8s:
	@echo "----------------- Deleting Deployed Services Commander from Kubernetes -------------------"
	@for deploy in $(DEPLOYS); do \
		deploy_lower=$$(echo $$deploy | tr 'A-Z' 'a-z'); \
		kubectl delete -f kubernetes/$$deploy_lower/$$deploy_lower-deployment.yaml --ignore-not-found=true; \
	done
	@-kubectl delete job langflow-benchmark postgres-build langflow-build
    @PODS=""

ps-k8s:
	@echo "----------------- Listing running Kubernetes pods -------------------"
	@kubectl get pods
	@echo "----------------- Listing Kubernetes services -------------------"
	@kubectl get services

# ---------------------------------------------------------------------------------
# --------------------------------- port forwarding -------------------------------
# ---------------------------------------------------------------------------------
port-forward-services:
	@for portforward in $(PORTFORWARD); do \
		echo "----------------- Forwarding $$portforward to localhost (in background)... -------------------"; \
		portforward_lower=$$(echo $$portforward | tr 'A-Z' 'a-z'); \
		config_map=$${portforward_lower}-config; \
        \
        PORT=$$(kubectl get configmap $$config_map -o jsonpath="{.data.$${portforward}_PORT}"); \
        REDIRECT_PORT=$$(kubectl get configmap $$config_map -o jsonpath="{.data.$${portforward}_REDIRECT_PORT}"); \
        export PORT REDIRECT_PORT; \
        nohup kubectl port-forward "$$(kubectl get pods -l app=$${portforward_lower} -o jsonpath='{.items[0].metadata.name}')" "$${REDIRECT_PORT}:$${PORT}" > /dev/null 2>&1 & \
        echo "Waiting for port-forward..." && sleep 5 && \
        echo "----------------- $$portforward should be accessible at localhost:$${REDIRECT_PORT} -------------------"; \
	done

# ---------------------------------------------------------------------------------
# ------------------------------------ WORKERS ------------------------------------
# ---------------------------------------------------------------------------------
check-workers:
	@set -e; \
	echo "--------------------------------------------------------------------"; \
	echo "--- Checking Langflow worker status ---"; \
	echo "--------------------------------------------------------------------"; \
	CONFIGURED_WORKERS=$$(kubectl get configmap langflow-config -o jsonpath='{.data.WEB_CONCURRENCY}' 2>/dev/null || true); \
	if [ -z "$$CONFIGURED_WORKERS" ]; then CONFIGURED_WORKERS="Not Set"; fi; \
	LANGFLOW_POD=$$(kubectl get pods -l app=langflow -o jsonpath='{.items[?(@.status.phase=="Running")].metadata.name}' 2>/dev/null | awk '{print $$1}'); \
	if [ -z "$$LANGFLOW_POD" ]; \
	then \
		echo "Langflow pod not found."; \
		RUNNING_PROCESSES=0; \
	else \
		COMMAND_TO_RUN="ps -ef | grep 'uvicorn.workers.UvicornWorker' | grep -v 'grep' | wc -l"; \
		RUNNING_PROCESSES=$$(kubectl exec "$$LANGFLOW_POD" -- sh -lc "$$COMMAND_TO_RUN" 2>/dev/null | tr -d '[:space:]' || echo 0); \
	fi; \
	[ -n "$$RUNNING_PROCESSES" ] || RUNNING_PROCESSES=0; \
	RUNNING_WORKERS=$$RUNNING_PROCESSES; \
	echo "Configured workers (in ConfigMap): $$CONFIGURED_WORKERS"; \
	echo "Running Gunicorn worker procs (in pod):    $$RUNNING_WORKERS"; \
	echo "Estimated worker processes:        $$RUNNING_WORKERS"

# ---------------------------------------------------------------------------------
# ------------------------------------ helpers ------------------------------------
# ---------------------------------------------------------------------------------
reset-db:
	@echo "----------------- Deleting Postgres deployment to release PVC -------------------"
	-kubectl delete deployment postgres
	@echo "----------------- Deleting Postgres Persistent Volume Claim (PVC) to WIPE DATA -------------------"
	-kubectl delete pvc postgres-pvc
	@echo "Database reset. Run 'make up-k8s' to re-initialize."
logs:
	@echo "----------------- Following logs for Postgres pod -------------------"
	@kubectl logs -f $$(kubectl get pods -l app=postgres -o jsonpath='{.items[0].metadata.name}')

init-langflow-users:
	@echo "----------------- Executing init scripts inside the Langflow container -------------------"
	@LANGFLOW_POD=$$(kubectl get pods -l app=langflow -o jsonpath='{.items[0].metadata.name}'); \
	echo "--- Creating /app/tmp directory inside the pod ---"; \
	kubectl exec "$${LANGFLOW_POD}" -- mkdir -p /app/tmp; \
	echo "--- Running init_service_user.py in pod: $${LANGFLOW_POD} ---"; \
	kubectl exec "$${LANGFLOW_POD}" -- python /app/init/python/init_service_user.py; \
	echo "--- Running init_public_user.py in pod: $${LANGFLOW_POD} ---"; \
	kubectl exec "$${LANGFLOW_POD}" -- python /app/init/python/init_public_user.py;
	@echo "----------------- Init scripts finished successfully. -------------------"

create-test-flow:
	@echo "--- Creating test flow for benchmarking ---"
	@LANGFLOW_POD=$$(kubectl get pods -l app=langflow -o jsonpath='{.items[0].metadata.name}'); \
	OUTPUT=$$(kubectl exec "$${LANGFLOW_POD}" -- python /app/init/python/init_benchmark_flow.py); \
	echo "$$OUTPUT"; \
	\
	FLOW_ID=$$(echo "$$OUTPUT" | grep 'BENCHMARK_DATA:FLOW_ID=' | cut -d'=' -f2 | tr -d '\r'); \
	API_KEY=$$(echo "$$OUTPUT" | grep 'BENCHMARK_DATA:API_KEY=' | cut -d'=' -f2 | tr -d '\r'); \
	\
	echo "Saving to ConfigMap and Secret..."; \
	kubectl patch configmap langflow-config --patch "{\"data\":{\"BENCHMARK_FLOW_ID\":\"$$FLOW_ID\"}}"; \
	kubectl patch secret langflow-secret --patch "{\"data\":{\"BENCHMARK_API_KEY\":\"$$(echo -n $$API_KEY | base64)\"}}"; \
	\
	echo "Saving to local files for verification..."; \
	echo "$$FLOW_ID" > .benchmark_flow_id; \
	echo "$$API_KEY" > .benchmark_api_key; \
	echo "Test flow created. Flow ID saved to .benchmark_flow_id, API key saved to .benchmark_api_key"

run-benchmark:
	@echo "--- Applying Benchmark RBAC and running Job ---"
	@kubectl apply -f kubernetes/benchmark/rbac.yaml
	@kubectl delete job langflow-benchmark --ignore-not-found=true
	@export REGISTRY_HOST=$$(minikube ip); \
	export FLOW_ID=$$(kubectl get configmap langflow-config -o jsonpath='{.data.BENCHMARK_FLOW_ID}'); \
    export API_KEY=$$(kubectl get secret langflow-secret -o jsonpath='{.data.BENCHMARK_API_KEY}' | base64 --decode); \
    export BENCHMARK_TYPE=$(BENCHMARK_TYPE); \
    export FIXED_WORKER_COUNT=$(FIXED_WORKER_COUNT); \
	envsubst < kubernetes/benchmark/benchmark-job.yaml | kubectl apply -f -
	@echo "--- Waiting for benchmark pod to start..."
	@BENCHMARK_POD_NAME=""; \
	while [ -z "$$BENCHMARK_POD_NAME" ]; do \
		echo -n "."; \
		sleep 1; \
		BENCHMARK_POD_NAME=$$(kubectl get pods -l job-name=langflow-benchmark -o jsonpath='{.items[0].metadata.name}' 2>/dev/null); \
	done; \
	echo "\nWaiting for benchmark pod to be ready..."; \
    kubectl wait --for=condition=ready pod/$$BENCHMARK_POD_NAME --timeout=120s; \
    echo "Benchmark pod is ready: $$BENCHMARK_POD_NAME. Streaming logs in real-time..."; \
    kubectl logs -f "$$BENCHMARK_POD_NAME"; \
	\
	echo "--- Log stream finished. Verifying final Job status... ---"; \
	sleep 5; \
	JOB_STATUS=$$(kubectl get job langflow-benchmark -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}'); \
	if [ "$$JOB_STATUS" != "True" ]; then \
		echo "!!! Benchmark job did not complete successfully. Check logs above for errors. !!!"; \
		exit 1; \
	fi; \
	\
	echo "--- Benchmark Job completed successfully. Retrieving final result. ---"; \
	minikube ssh 'sudo cat /app/.optimal_workers' > .optimal_workers; \
	echo "Optimal worker count saved to local .optimal_workers file."

monitor-db:
	@bash kubernetes/benchmark/monitoring/db.sh

monitor-pgbouncer:
	@bash kubernetes/benchmark/monitoring/bouncer.sh