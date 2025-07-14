namespace ZoneAPI.Models
{
    public class Doctor
    {
        public int Id { get; set; }
        public string Name { get; set; } = string.Empty;
        public string Specialization { get; set; } = string.Empty;
        public virtual ICollection<Appointment>? Appointments { get; set; }
    }
}
