apiVersion: v1
kind: LimitRange
metadata:
  name: resource-limits
  namespace: default
spec:
  limits:
  - default:
      memory: ${LIMIT_MEM}
      cpu: "${LIMIT_CPU}"
    defaultRequest:
      memory: ${REQUEST_MEM}
      cpu: "${REQUEST_CPU}"
    type: Container
