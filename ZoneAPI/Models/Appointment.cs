using Microsoft.EntityFrameworkCore;
using static System.Runtime.InteropServices.JavaScript.JSType;
using System.ComponentModel.DataAnnotations;

namespace ZoneAPI.Models
{
    public class Appointment : IValidatableObject
    {
        public int Id { get; set; }
        public DateTime Date { get; set; }
        public int DoctorId { get; set; }
        public virtual Doctor Doctor { get; set; }
        public int PatientId { get; set; }
        public virtual Patient Patient { get; set; }

        public IEnumerable<ValidationResult> Validate(ValidationContext validationContext)
        {
            // Check if the patient already has an appointment or if the doctor already has 5 appointments on the given date
            var db = validationContext.GetService(typeof(ApplicationDbContext)) as ApplicationDbContext;
            if (db != null)
            {
                var appointments = db.Appointments
                    .Where(a => a.Date.Date == Date.Date)
                    .ToList();

                if (appointments.Any(a => a.PatientId == PatientId))
                {
                    yield return new ValidationResult("Patient already has an appointment on the given date.", new[] { nameof(Date) });
                }

                if (appointments.Count(a => a.DoctorId == DoctorId) >= 5)
                {
                    yield return new ValidationResult("Doctor already has 5 appointments on the given date.", new[] { nameof(Date) });
                }

                if (Date.TimeOfDay < new TimeSpan(10, 0, 0) || Date.TimeOfDay > new TimeSpan(15, 0, 0))
                {
                    yield return new ValidationResult("Appointments can only be scheduled between 10am and 3pm.", new[] { nameof(Date) });
                }
            }
        }
    }



}