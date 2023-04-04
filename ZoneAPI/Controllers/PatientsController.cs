using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json.Serialization;
using System.Text.Json;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZoneAPI.Models;

namespace ZoneAPI.Controllers
{
    [Route("api/[controller]")]
    [ApiController]
    public class PatientsController : ControllerBase
    {
        private readonly ApplicationDbContext _context;

        public PatientsController(ApplicationDbContext context)
        {
            _context = context;
        }

        // GET: api/Patients
        [HttpGet]
        public async Task<ActionResult<IEnumerable<Patient>>> GetPatients()
        {
            var options = new JsonSerializerOptions
            {
                ReferenceHandler = ReferenceHandler.Preserve
            };

            if (_context.Patients == null)
          {
              return NotFound();
          }
            var patientsList = await _context.Patients
                .Include(p => p.Appointments)
                .ToListAsync();
            var json = JsonSerializer.Serialize(patientsList, options);
            return Ok(json);
        }

        // GET: api/Patients/5
        [HttpGet("{id}")]
        public async Task<ActionResult<Patient>> GetPatient(int id)
        {
            var options = new JsonSerializerOptions
            {
                ReferenceHandler = ReferenceHandler.Preserve
            };

          if (_context.Patients == null)
          {
              return NotFound();
          }
            var patient = await _context.Patients
                .Include(p => p.Appointments)
                .FirstOrDefaultAsync(p => p.Id == id);

            if (patient == null)
            {
                return NotFound();
            }

            var json = JsonSerializer.Serialize(patient, options);
            return Ok(json);
        }

        // PUT: api/Patients/5
        // To protect from overposting attacks, see https://go.microsoft.com/fwlink/?linkid=2123754
        [HttpPut("{id}")]
        public async Task<IActionResult> PutPatient(int id, Patient patient)
        {
            if (id != patient.Id)
            {
                return BadRequest();
            }

            _context.Entry(patient).State = EntityState.Modified;

            try
            {
                await _context.SaveChangesAsync();
            }
            catch (DbUpdateConcurrencyException)
            {
                if (!PatientExists(id))
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

        // POST: api/Patients
        // To protect from overposting attacks, see https://go.microsoft.com/fwlink/?linkid=2123754
        [HttpPost]
        public async Task<ActionResult<Patient>> PostPatient(Patient patient)
        {
          if (_context.Patients == null)
          {
              return Problem("Entity set 'ApplicationDbContext.Patients'  is null.");
          }
            _context.Patients.Add(patient);
            await _context.SaveChangesAsync();

            return CreatedAtAction("GetPatient", new { id = patient.Id }, patient);
        }

        // DELETE: api/Patients/5
        [HttpDelete("{id}")]
        public async Task<IActionResult> DeletePatient(int id)
        {
            if (_context.Patients == null)
            {
                return NotFound();
            }
            var patient = await _context.Patients.FindAsync(id);
            if (patient == null)
            {
                return NotFound();
            }

            _context.Patients.Remove(patient);
            await _context.SaveChangesAsync();

            return NoContent();
        }


        private bool PatientExists(int id)
        {
            return (_context.Patients?.Any(e => e.Id == id)).GetValueOrDefault();
        }
    }
}
