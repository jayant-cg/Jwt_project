using System;
using System.Collections.Generic;
using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.IdentityModel.Tokens;
using UserAuthApi.Data;
using UserAuthApi.DTOs;
using UserAuthApi.Models;

namespace UserAuthApi.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class AuthController : ControllerBase
    {
        private readonly AppDbContext _context;
        private readonly IConfiguration _configuration;

        public AuthController(AppDbContext context, IConfiguration configuration)
        {
            _context = context;
            _configuration = configuration;
        }

        // POST api/auth/register
        [AllowAnonymous]
        [HttpPost("register")]
        public async Task<IActionResult> Register([FromBody] RegisterDto dto)
        {
            if (string.IsNullOrWhiteSpace(dto.Name) ||
                string.IsNullOrWhiteSpace(dto.Email) ||
                string.IsNullOrWhiteSpace(dto.Phone) ||
                string.IsNullOrWhiteSpace(dto.Password))
            {
                return BadRequest(new { message = "All fields (name, email, phone, password) are required." });
            }

            bool emailExists = await _context.Users.AnyAsync(u => u.Email == dto.Email);
            if (emailExists)
            {
                return Conflict(new { message = "A user with this email already exists." });
            }

            var user = new User
            {
                Name = dto.Name,
                Email = dto.Email,
                Phone = dto.Phone,
                Password = BCrypt.Net.BCrypt.HashPassword(dto.Password)
            };

            _context.Users.Add(user);
            await _context.SaveChangesAsync();

            return Ok(new { message = "User registered successfully.", userId = user.Id });
        }

        // POST api/auth/signin
        [AllowAnonymous]
        [HttpPost("signin")]
        public async Task<IActionResult> SignIn([FromBody] SignInDto dto)
        {
            var loginResult = await ValidateUserCredentialsAndGenerateToken(dto);
            if (loginResult == null)
            {
                return StatusCode(401, new { message = "Invalid email or password." });
            }

            var (user, token) = loginResult.Value;

            return Ok(new
            {
                message = "Sign in successful.",
                userId = user.Id,
                name = user.Name,
                token = token
            });
        }

        // POST api/auth/login
        [AllowAnonymous]
        [HttpPost("login")]
        public async Task<IActionResult> Login([FromBody] SignInDto dto)
        {
            if (string.IsNullOrWhiteSpace(dto.Email) || string.IsNullOrWhiteSpace(dto.Password))
            {
                return BadRequest(new { message = "Email and password are required." });
            }

            var loginResult = await ValidateUserCredentialsAndGenerateToken(dto);
            if (loginResult == null)
            {
                return StatusCode(401, new { message = "Invalid email or password." });
            }

            var (user, token) = loginResult.Value;

            return Ok(new
            {
                message = "Login successful.",
                userId = user.Id,
                name = user.Name,
                email = user.Email,
                token = token
            });
        }

        private async Task<(User User, string Token)?> ValidateUserCredentialsAndGenerateToken(SignInDto dto)
        {
            var user = await _context.Users.FirstOrDefaultAsync(u => u.Email == dto.Email);
            if (user == null)
            {
                return null;
            }

            bool passwordMatch = await VerifyPasswordAsync(user, dto.Password);
            if (!passwordMatch)
            {
                return null;
            }

            return (user, GenerateJwtToken(user));
        }

        private async Task<bool> VerifyPasswordAsync(User user, string providedPassword)
        {
            if (string.IsNullOrWhiteSpace(user.Password))
            {
                return false;
            }

            if (LooksLikeBcryptHash(user.Password))
            {
                return TryVerifyBcrypt(providedPassword, user.Password);
            }

            // Backward compatibility: if older data has plain-text passwords, allow login once and upgrade.
            if (!string.Equals(user.Password, providedPassword, StringComparison.Ordinal))
            {
                return false;
            }

            user.Password = BCrypt.Net.BCrypt.HashPassword(providedPassword);
            await _context.SaveChangesAsync();
            return true;
        }

        private static bool TryVerifyBcrypt(string providedPassword, string storedHash)
        {
            try
            {
                return BCrypt.Net.BCrypt.Verify(providedPassword, NormalizeBcryptHashVersion(storedHash));
            }
            catch (BCrypt.Net.SaltParseException)
            {
                return false;
            }
            catch (FormatException)
            {
                return false;
            }
        }

        private static bool LooksLikeBcryptHash(string hash)
        {
            return hash.StartsWith("$2a$", StringComparison.Ordinal) ||
                   hash.StartsWith("$2b$", StringComparison.Ordinal) ||
                   hash.StartsWith("$2y$", StringComparison.Ordinal) ||
                   hash.StartsWith("$2x$", StringComparison.Ordinal);
        }

        private static string NormalizeBcryptHashVersion(string hash)
        {
            if (hash.StartsWith("$2y$", StringComparison.Ordinal) ||
                hash.StartsWith("$2x$", StringComparison.Ordinal))
            {
                return "$2a$" + hash.Substring(4);
            }

            return hash;
        }

        private string GenerateJwtToken(User user)
        {
            var jwtSettings = _configuration.GetSection("Jwt");
            var issuer = jwtSettings["Issuer"];
            var audience = jwtSettings["Audience"];
            var key = jwtSettings["Key"];

            if (string.IsNullOrWhiteSpace(issuer) ||
                string.IsNullOrWhiteSpace(audience) ||
                string.IsNullOrWhiteSpace(key))
            {
                throw new InvalidOperationException("JWT settings are missing or invalid in configuration.");
            }

            var claims = new List<Claim>
            {
                new(JwtRegisteredClaimNames.Sub, user.Id.ToString()),
                new(JwtRegisteredClaimNames.Jti, Guid.NewGuid().ToString()),
                new(ClaimTypes.NameIdentifier, user.Id.ToString()),
                new(ClaimTypes.Name, user.Name),
                new(ClaimTypes.Email, user.Email)
            };

            if (!string.IsNullOrWhiteSpace(user.Phone))
            {
                claims.Add(new Claim(ClaimTypes.MobilePhone, user.Phone));
            }

            var signingKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(key));
            var credentials = new SigningCredentials(signingKey, SecurityAlgorithms.HmacSha256);

            var token = new JwtSecurityToken(
                issuer: issuer,
                audience: audience,
                claims: claims,
                expires: DateTime.UtcNow.AddHours(2),
                signingCredentials: credentials);

            return new JwtSecurityTokenHandler().WriteToken(token);
        }
    }
}
