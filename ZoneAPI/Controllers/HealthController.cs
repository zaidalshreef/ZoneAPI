using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZoneAPI.Models;

namespace ZoneAPI.Controllers
{
    [ApiController]
    [Route("[controller]")]
    public class HealthController : ControllerBase
    {
        private readonly ApplicationDbContext _context;
        private readonly ILogger<HealthController> _logger;

        public HealthController(ApplicationDbContext context, ILogger<HealthController> logger)
        {
            _context = context;
            _logger = logger;
        }

        [HttpGet]
        public async Task<IActionResult> GetHealth()
        {
            try
            {
                // Test database connectivity
                await _context.Database.CanConnectAsync();
                
                // Get database info
                var doctorCount = await _context.Doctors.CountAsync();
                var patientCount = await _context.Patients.CountAsync();
                var appointmentCount = await _context.Appointments.CountAsync();
                
                var healthStatus = new
                {
                    Status = "Healthy",
                    Timestamp = DateTime.UtcNow,
                    Database = new
                    {
                        Connected = true,
                        DoctorCount = doctorCount,
                        PatientCount = patientCount,
                        AppointmentCount = appointmentCount
                    },
                    Application = new
                    {
                        Environment = Environment.GetEnvironmentVariable("ASPNETCORE_ENVIRONMENT"),
                        MachineName = Environment.MachineName,
                        Version = "1.0.0"
                    }
                };

                _logger.LogInformation("Health check successful");
                return Ok(healthStatus);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Health check failed");
                
                var unhealthyStatus = new
                {
                    Status = "Unhealthy",
                    Timestamp = DateTime.UtcNow,
                    Error = ex.Message,
                    Database = new
                    {
                        Connected = false
                    }
                };

                return StatusCode(503, unhealthyStatus);
            }
        }
    }
} 