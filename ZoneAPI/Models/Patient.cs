namespace ZoneAPI.Models
{

    public class Patient
    {
        public int Id { get; set; }
        public string Name { get; set; } = string.Empty;
        public virtual ICollection<Appointment>? Appointments { get; set; }
    }
}
