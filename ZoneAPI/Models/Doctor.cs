namespace ZoneAPI.Models
{
    public class Doctor
    {
        public int Id { get; set; }
        public string Name { get; set; }
        public string Specialization { get; set; }
        public virtual ICollection<Appointment> Appointments { get; set; }
    }
}
