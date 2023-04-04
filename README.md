<div align="center">

# ZoneAPI

</div>

## Table of Contents

- [Introduction](#introduction)
- [Technologies](#technologies)
- [Setup](#setup)
- [API Endpoints](#api-endpoints)

## Introduction

ZoneAPI is a RESTful web service that provides appointment scheduling functionality. The API allows users to create, retrieve, update, and delete appointments, doctors, and patients. 

## Technologies

The following technologies were used to build this project:

- .NET Core 7
- Entity Framework Core
- PostgreSQL
- Visual Studio Code
- Git

Postman Collection
A Postman collection is available for testing the API endpoints. To use the collection, follow these steps:

Open Postman and click on the Import button in the top left corner.
Select the Import From file
Click on the Import button.
You should now see the ZoneAPI collection in your Postman workspace. You can use this collection to test the API endpoints.


## Setup

1. Clone the repository:

git clone https://github.com/zaidalshreef/ZoneAPI.git


2. Navigate to the project directory:


3. Install the required packages:


4. Start the API:


## API Endpoints

The following API endpoints are available:

### Appointments

- `GET /api/appointments` - Returns a list of all appointments.
- `GET /api/appointments/{id}` - Returns an appointment with the specified `id`.
- `POST /api/appointments` - Creates a new appointment.
- `PUT /api/appointments/{id}` - Updates an appointment with the specified `id`.
- `DELETE /api/appointments/{id}` - Deletes an appointment with the specified `id`.

### Doctors

- `GET /api/doctors` - Returns a list of all doctors.
- `GET /api/doctors/{id}` - Returns a doctor with the specified `id`.
- `POST /api/doctors` - Creates a new doctor.
- `PUT /api/doctors/{id}` - Updates a doctor with the specified `id`.
- `DELETE /api/doctors/{id}` - Deletes a doctor with the specified `id`.

### Patients

- `GET /api/patients` - Returns a list of all patients.
- `GET /api/patients/{id}` - Returns a patient with the specified `id`.
- `POST /api/patients` - Creates a new patient.
- `PUT /api/patients/{id}` - Updates a patient with the specified `id`.
- `DELETE /api/patients/{id}` - Deletes a patient with the specified `id`.

All API endpoints support JSON request.
