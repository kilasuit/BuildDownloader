// See https://aka.ms/new-console-template for more information
using System;
using System.Reflection;

// Get the assembly
Assembly assembly = Assembly.GetExecutingAssembly();

// Get the product name
var productAttribute = (AssemblyTitleAttribute)Attribute.GetCustomAttribute(assembly, typeof(AssemblyTitleAttribute));
string productName = productAttribute?.Title ?? "Unknown Product";

// Get the company name
var companyAttribute = (AssemblyCompanyAttribute)Attribute.GetCustomAttribute(assembly, typeof(AssemblyCompanyAttribute));
string companyName = companyAttribute?.Company ?? "Unknown Company";

// Get the copyright information
var copyrightAttribute = (AssemblyCopyrightAttribute)Attribute.GetCustomAttribute(assembly, typeof(AssemblyCopyrightAttribute));
string copyrightInfo = copyrightAttribute?.Copyright ?? "Unknown Copyright";

// Output the information

Console.WriteLine("Hello PSCommunity - It's a great day today isn't it?");
Console.WriteLine($"Product: {productName}");
Console.WriteLine($"Company: {companyName}");
Console.WriteLine($"Copyright: {copyrightInfo}");

