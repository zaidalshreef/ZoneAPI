using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using System.Text.Json.Serialization;
using System.Text.Json;
using ZoneAPI.Models;
using System.Numerics;

namespace ZoneAPI.Controllers
{
    [Route("api/[controller]")]
    [ApiController]
    public class DoctorsController : ControllerBase
    {
        private readonly ApplicationDbContext _context;

        public DoctorsController(ApplicationDbContext context)
        {
            _context = context;
        }

        // GET: api/Doctors
        [HttpGet]
        public async Task<ActionResult<IEnumerable<Doctor>>> GetDoctors()
        {

            var options = new JsonSerializerOptions
            {
                ReferenceHandler = ReferenceHandler.Preserve
            };

            if (_context.Doctors == null)
          {
              return NotFound();
          }
            var doctorsList = await _context.Doctors
                .Include(d => d.Appointments)
                .ToListAsync();

            var json = JsonSerializer.Serialize(doctorsList, options);
            return Ok(json);
        
        }

        // GET: api/Doctors/5
        [HttpGet("{id}")]
        public async Task<ActionResult<Doctor>> GetDoctor(int id)
        {
            var options = new JsonSerializerOptions
            {
                ReferenceHandler = ReferenceHandler.Preserve
            };

          if (_context.Doctors == null)
          {
              return NotFound();
          }
            var doctor = await _context.Doctors
                .Include(d => d.Appointments)
                .FirstOrDefaultAsync(d => d.Id == id);

            if (doctor == null)
            {
                return NotFound();
            }

            var json = JsonSerializer.Serialize(doctor, options);
            
            return Ok(json);
        }

        // PUT: api/Doctors/5
        // To protect from overposting attacks, see https://go.microsoft.com/fwlink/?linkid=2123754
        [HttpPut("{id}")]
        public async Task<IActionResult> PutDoctor(int id, Doctor doctor)
        {
            if (id != doctor.Id)
            {
                return BadRequest();
            }

            _context.Entry(doctor).State = EntityState.Modified;

            try
            {
                await _context.SaveChangesAsync();
            }
            catch (DbUpdateConcurrencyException)
            {
                if (!DoctorExists(id))
                {
                    return NotFound();
                }
                else
                {
                    throw;
                }
            }

            return NoContent();
        }

        // POST: api/Doctors
        // To protect from overposting attacks, see https://go.microsoft.com/fwlink/?linkid=2123754
        [HttpPost]
        public async Task<ActionResult<Doctor>> PostDoctor(Doctor doctor)
        {
          if (_context.Doctors == null)
          {
              return Problem("Entity set 'ApplicationDbContext.Doctors'  is null.");
          }
            _context.Doctors.Add(doctor);
            await _context.SaveChangesAsync();

            return CreatedAtAction("GetDoctor", new { id = doctor.Id }, doctor);
        }

        // DELETE: api/Doctors/5
        [HttpDelete("{id}")]
        public async Task<IActionResult> DeleteDoctor(int id)
        {
            if (_context.Doctors == null)
            {
                return NotFound();
            }
            var doctor = await _context.Doctors.FindAsync(id);
            if (doctor == null)
            {
                return NotFound();
            }

            _context.Doctors.Remove(doctor);
            await _context.SaveChangesAsync();

            return NoContent();
        }

        private bool DoctorExists(int id)
        {
            return (_context.Doctors?.Any(e => e.Id == id)).GetValueOrDefault();
        }


        // GET: api/Doctors/5/appointments?date=2023-04-03
        [HttpGet("{id}/appointments")]
        public async Task<ActionResult<IEnumerable<Appointment>>> GetAppointmentsForDay(int id, [FromQuery] DateTime date)
        {
            var options = new JsonSerializerOptions
            {
                ReferenceHandler = ReferenceHandler.Preserve

            };

            try
            {
                
                var appointments = await _context.Appointments
                    .Where(a => a.DoctorId == id && a.Date.Date == date.Date)
                    .Include(a => a.Doctor)
                    .Include(a => a.Patient)
                    .ToListAsync();

                if (appointments == null || appointments.Count == 0)
                {
                    return NotFound();
                }

                var json = JsonSerializer.Serialize(appointments, options);

                return Ok(json);
            }
            catch (Exception ex)
            {
                return StatusCode(500, $"Error retrieving appointments: {ex.Message}");
            }
        }

    }
    }
