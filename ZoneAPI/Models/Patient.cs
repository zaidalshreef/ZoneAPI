namespace ZoneAPI.Models
{

    public class Patient
    {
        public int Id { get; set; }
        public string Name { get; set; }
        public virtual ICollection<Appointment>? Appointments { get; set; }
    }
}
