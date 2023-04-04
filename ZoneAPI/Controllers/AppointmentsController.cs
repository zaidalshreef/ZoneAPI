using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.Linq;
using System.Text.Json.Serialization;
using System.Text.Json;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Http.HttpResults;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using NodaTime;
using ZoneAPI.Models;

namespace ZoneAPI.Controllers
{
    [Route("api/[controller]")]
    [ApiController]
    public class AppointmentsController : ControllerBase
    {
        private readonly ApplicationDbContext _context;

        public AppointmentsController(ApplicationDbContext context)
        {
            _context = context;
        }

        // GET: api/Appointments
        [HttpGet]
        public async Task<ActionResult<IEnumerable<Appointment>>> GetAppointments()
        {
            var options = new JsonSerializerOptions
            {
                ReferenceHandler = ReferenceHandler.Preserve
            };

            var appointmentsList = await _context.Appointments
                .Include(a => a.Doctor)
                .Include(a => a.Patient)
                .ToListAsync();

            if (appointmentsList == null)
            {
                return NotFound();
            }

            var json = JsonSerializer.Serialize(appointmentsList, options);
            return Ok(json);
        }


        // GET: api/Appointments/5
        [HttpGet("{id}")]
        public async Task<ActionResult<Appointment>> GetAppointment(int id)
        {
            var options = new JsonSerializerOptions
            {
                ReferenceHandler = ReferenceHandler.Preserve
            };

            var appointment = await _context.Appointments
                .Include(a => a.Doctor)
                .Include(a => a.Patient)
                .FirstOrDefaultAsync(a => a.Id == id);

            if (appointment == null)
            {
                return NotFound();
            }

            var json = JsonSerializer.Serialize(appointment, options);
            return Ok(json);
        }


        // PUT: api/Appointments/5
        // To protect from overposting attacks, see https://go.microsoft.com/fwlink/?linkid=2123754
        [HttpPut("{id}")]
        public async Task<IActionResult> PutAppointment(int id, Appointment appointment)
        {
            if (id != appointment.Id)
            {
                return BadRequest();
            }

            // Validate the appointment
            var validationContext = new ValidationContext(appointment, serviceProvider: null, items: null);
            var validationResults = new List<ValidationResult>();
            var isValid = Validator.TryValidateObject(appointment, validationContext, validationResults, validateAllProperties: true);

            if (!isValid)
            {
                return BadRequest(validationResults);
            }

            _context.Entry(appointment).State = EntityState.Modified;

            try
            {
                await _context.SaveChangesAsync();
            }
            catch (DbUpdateConcurrencyException)
            {
                if (!AppointmentExists(id))
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

        // POST: api/Appointments
        // To protect from overposting attacks, see https://go.microsoft.com/fwlink/?linkid=2123754
        [HttpPost]
        public async Task<ActionResult<Appointment>> PostAppointment(Appointment appointment)
        {
            if (_context.Appointments == null)
            {
                return Problem("Entity set 'ApplicationDbContext.Appointments'  is null.");
            }

            var validationContext = new ValidationContext(appointment, serviceProvider: null, items: null);
            var validationResults = new List<ValidationResult>();
            bool isValid = Validator.TryValidateObject(appointment, validationContext, validationResults, true);
            if (!isValid)
            {
                return BadRequest(validationResults);
            }

            _context.Appointments.Add(appointment);
            await _context.SaveChangesAsync();

            return CreatedAtAction("GetAppointment", new { id = appointment.Id }, appointment);
        }

        // DELETE: api/Appointments/5
        [HttpDelete("{id}")]
        public async Task<IActionResult> DeleteAppointment(int id)
        {
            if (_context.Appointments == null)
            {
                return NotFound();
            }
            var appointment = await _context.Appointments.FindAsync(id);
            if (appointment == null)
            {
                return NotFound();
            }

            _context.Appointments.Remove(appointment);
            await _context.SaveChangesAsync();

            return NoContent();
        }

        [HttpGet]
        [Route("date/{date}")]
        public async Task<ActionResult<IEnumerable<Appointment>>> GetAppointmentsForDate(DateTime date)
        {

            var appointments = await _context.Appointments
                .Where(a => a.Date.Date == date.Date)
                .ToListAsync();

            if (appointments == null || appointments.Count == 0)
            {
                return NotFound();
            }

            return Ok(appointments);
        }


        private bool AppointmentExists(int id)
        {
            return (_context.Appointments?.Any(e => e.Id == id)).GetValueOrDefault();
        }


    }
}
