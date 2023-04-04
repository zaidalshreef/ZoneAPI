using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Pomelo.EntityFrameworkCore.MySql.Infrastructure;
using Microsoft.EntityFrameworkCore.Design;
using ZoneAPI.Models;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddControllers();

builder.Services.AddDbContextPool<ApplicationDbContext>(options => {
    options.UseNpgsql(builder.Configuration.GetConnectionString("PostgreSQLConnection"));
    });

builder.Services.AddEndpointsApiExplorer();

var app = builder.Build();

AppContext.SetSwitch("Npgsql.EnableLegacyTimestampBehavior", true);

app.UseHttpsRedirection();

app.UseAuthorization();

app.MapControllers();

app.Run();