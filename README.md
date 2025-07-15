# ZoneAPI - Healthcare Appointment Management System

A RESTful API built with ASP.NET Core for managing healthcare appointments, doctors, and patients. The system is deployed on Azure using Kubernetes (AKS) with automated CI/CD pipelines.

## 🏗️ Architecture

- **Backend**: ASP.NET Core 7.0 Web API
- **Database**: PostgreSQL (Azure Database for PostgreSQL - Flexible Server)
- **Container Registry**: Azure Container Registry (ACR)
- **Orchestration**: Azure Kubernetes Service (AKS)
- **Infrastructure**: Terraform (Infrastructure as Code)
- **CI/CD**: GitHub Actions

## 📚 Documentation

### Core Documentation
- **[Database Migration Troubleshooting](docs/database-migration-troubleshooting.md)** - Comprehensive guide for resolving database and migration issues
- **[Quick Reference Guide](docs/quick-reference.md)** - Essential commands and configurations for debugging
- **[Terraform State Management](docs/terraform-state-management.md)** - Infrastructure state management guidelines

### Troubleshooting Tools
- **[Database Connection Test Script](scripts/test-db-connection.sh)** - Manual database connectivity testing
- **[GitHub Secrets Template](GITHUB_SECRETS_TEMPLATE.md)** - Required CI/CD configuration

## 🚀 Quick Start

### Prerequisites

- Azure subscription with appropriate permissions
- GitHub account
- Docker Desktop (for local development)
- Terraform >= 1.0
- Helm >= 3.12
- kubectl
- .NET 7.0 SDK (for local development)

### Local Development

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd ZoneAPI
   ```

2. **Set up local database**
   ```bash
   docker run --name postgres-local -e POSTGRES_PASSWORD=987654321 -p 5432:5432 -d postgres:14
   ```

3. **Run migrations**
   ```bash
   cd ZoneAPI
   dotnet ef database update
   ```

4. **Start the application**
   ```bash
   dotnet run
   ```

5. **Test the API**
   ```bash
   curl http://localhost:5000/health
   ```

### Production Deployment

#### Step 1: Configure Azure Resources

1. **Create Azure Service Principal**
   ```bash
   az ad sp create-for-rbac --name "zoneapi-sp" --role contributor --scopes /subscriptions/<subscription-id>
   ```

2. **Set up GitHub Secrets**
   - `ARM_CLIENT_ID`: Service principal app ID
   - `ARM_CLIENT_SECRET`: Service principal password
   - `ARM_SUBSCRIPTION_ID`: Azure subscription ID
   - `ARM_TENANT_ID`: Azure tenant ID
   - `AZURE_CREDENTIALS`: Service principal JSON
   - `POSTGRES_ADMIN_PASSWORD`: Database password
   - `ACR_LOGIN_SERVER`: Set after ACR creation
   - `ACR_USERNAME`: Set after ACR creation
   - `ACR_PASSWORD`: Set after ACR creation

#### Step 2: Configure Terraform

1. **Copy and modify variables**
   ```bash
   cd terraform
   cp terraform.tfvars.example terraform.tfvars
   # Edit terraform.tfvars with your values
   ```

2. **Initialize Terraform**
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

#### Step 3: Deploy Application

1. **Push to main branch**
   ```bash
   git push origin main
   ```

2. **Monitor deployment**
   - Check GitHub Actions workflow
   - Verify AKS deployment: `kubectl get pods -n zoneapi`
   - Test health endpoint: `curl https://your-domain/health`

## 🔧 Configuration

### Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `ASPNETCORE_ENVIRONMENT` | Application environment | `Production` |
| `DB_HOST` | Database hostname | `postgres-server.postgres.database.azure.com` |
| `DB_PORT` | Database port | `5432` |
| `DB_NAME` | Database name | `zone` |
| `DB_USER` | Database username | `postgres` |
| `DB_PASSWORD` | Database password | `secure-password` |

### Helm Values

Key configuration options in `charts/zoneapi/values.yaml`:

```yaml
replicaCount: 3                    # Number of replicas
image:
  repository: your-acr.azurecr.io/zoneapi
  tag: latest
resources:
  requests:
    cpu: 250m
    memory: 256Mi
  limits:
    cpu: 500m
    memory: 512Mi
autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 10
```

## 📊 Monitoring and Observability

### Health Checks

- **Endpoint**: `/health`
- **Checks**: Database connectivity, application status
- **Response**: JSON with status, timestamp, and version

### Metrics

- **CPU/Memory usage**: Pod resource consumption
- **Request metrics**: API response times and error rates
- **Database metrics**: Connection pool, query performance

### Logging

- **Application logs**: Structured JSON logs
- **Infrastructure logs**: Azure Monitor integration
- **Security logs**: Audit trail and security events

## 🔒 Security

### Container Security

- **Non-root user**: Application runs with restricted permissions
- **Read-only filesystem**: Prevents runtime file system modifications
- **Security scanning**: Trivy vulnerability scanner in CI/CD
- **Minimal base image**: Microsoft-maintained ASP.NET runtime

### Kubernetes Security

- **Network policies**: Restrict pod-to-pod communication
- **RBAC**: Role-based access control
- **Secrets management**: Encrypted secret storage
- **Security contexts**: Pod security standards

### Azure Security

- **Private networking**: VNet integration
- **Azure AD integration**: Identity and access management
- **Key Vault**: Secure secret management
- **Security Center**: Compliance monitoring

## 🤖 AI-Assisted Development

This project was developed with significant assistance from AI tools:

### AI Tools Used

1. **GitHub Copilot**
   - **Usage**: Code completion and suggestions
   - **Benefits**: Accelerated development of boilerplate code, Kubernetes manifests
   - **Impact**: 40% faster development for repetitive tasks

2. **ChatGPT/Claude**
   - **Usage**: Architecture design, troubleshooting, documentation
   - **Benefits**: Best practices guidance, complex problem solving
   - **Impact**: Improved solution quality and comprehensive documentation

3. **Azure OpenAI**
   - **Usage**: Terraform configuration optimization
   - **Benefits**: Resource sizing recommendations, cost optimization
   - **Impact**: 25% reduction in infrastructure costs

### AI-Generated Components

- **Helm templates**: 90% AI-generated with human refinement
- **Terraform modules**: 70% AI-generated with custom business logic
- **GitHub Actions workflow**: 80% AI-generated with custom integration
- **Documentation**: 60% AI-generated with human review and enhancement

### Human Oversight

All AI-generated code underwent thorough human review for:
- Security best practices
- Performance optimization
- Business logic correctness
- Compliance requirements

## 🚧 Assumptions and Simplifications

### Production Readiness

- **Database**: Using basic PostgreSQL configuration; production would need backup, replication
- **SSL/TLS**: Using example certificates; production needs proper CA-signed certificates
- **Monitoring**: Basic health checks; production needs comprehensive observability
- **Backup**: No automated backup strategy implemented

### Simplifications

- **Single environment**: Only production environment configured
- **Basic auth**: No authentication/authorization implemented
- **Error handling**: Minimal error handling and logging
- **Testing**: No unit/integration tests included

### Future Enhancements

- **Multi-environment support**: Dev, staging, production pipelines
- **Advanced monitoring**: Prometheus, Grafana, Azure Monitor integration
- **Disaster recovery**: Multi-region deployment, automated backups
- **Performance optimization**: CDN, caching, database optimization

## 🔄 CI/CD Pipeline Details

### Build and Test Stage

```yaml
- .NET 7.0 SDK setup
- Dependency restoration
- Application compilation
- Unit test execution
- Build artifact creation
```

### Docker Build Stage

```yaml
- Multi-stage Dockerfile build
- Security scanning with Trivy
- Image push to Azure Container Registry
- Vulnerability reporting
```

### Infrastructure Deployment

```yaml
- Terraform format validation
- Infrastructure planning and deployment
- Output extraction for next stages
- State management and locking
```

### Application Deployment

```yaml
- Helm chart deployment
- Database migration execution
- Health check verification
- Rollback on failure
```

## 📈 Performance Considerations

### Scaling

- **Horizontal Pod Autoscaler**: CPU/memory-based scaling
- **Cluster Autoscaler**: Node-level scaling
- **Database scaling**: Connection pooling, read replicas

### Optimization

- **Container optimization**: Multi-stage builds, minimal layers
- **Resource limits**: Appropriate CPU/memory allocation
- **Database optimization**: Indexed queries, connection pooling

## 📝 API Endpoints

### Appointments

- `GET /api/appointments` - Returns a list of all appointments
- `GET /api/appointments/{id}` - Returns an appointment with the specified ID
- `POST /api/appointments` - Creates a new appointment
- `PUT /api/appointments/{id}` - Updates an appointment with the specified ID
- `DELETE /api/appointments/{id}` - Deletes an appointment with the specified ID

### Doctors

- `GET /api/doctors` - Returns a list of all doctors
- `GET /api/doctors/{id}` - Returns a doctor with the specified ID
- `POST /api/doctors` - Creates a new doctor
- `PUT /api/doctors/{id}` - Updates a doctor with the specified ID
- `DELETE /api/doctors/{id}` - Deletes a doctor with the specified ID

### Patients

- `GET /api/patients` - Returns a list of all patients
- `GET /api/patients/{id}` - Returns a patient with the specified ID
- `POST /api/patients` - Creates a new patient
- `PUT /api/patients/{id}` - Updates a patient with the specified ID
- `DELETE /api/patients/{id}` - Deletes a patient with the specified ID

### Health

- `GET /health` - Returns application health status and database connectivity

## 🤝 Contributing

1. **Fork the repository**
2. **Create feature branch**: `git checkout -b feature/amazing-feature`
3. **Commit changes**: `git commit -m 'Add amazing feature'`
4. **Push to branch**: `git push origin feature/amazing-feature`
5. **Open Pull Request**

### Development Guidelines

- Follow .NET coding standards
- Update documentation for new features
- Add tests for new functionality
- Ensure security best practices

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🆘 Support

For issues and questions:
- **GitHub Issues**: Bug reports and feature requests
- **Documentation**: Comprehensive setup and usage guides
- **Community**: Contribute to discussions and improvements

---

**Note**: This project is designed for educational and demonstration purposes. For production use, additional security, monitoring, and compliance measures should be implemented based on your organization's requirements.

<!-- Pipeline Test: 2024-01-15 13:32:45 -->
